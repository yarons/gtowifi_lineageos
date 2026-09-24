/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

// AOSP's default health HAL, plus one rule: a battery that stays below its declared minimum voltage
// while discharging is empty, whatever its gauge says.
//
// The kernel's gauge counts charge, and the count cannot see the end of the pack coming: at the
// bottom of the curve the voltage under load collapses faster than the last percent drains. Playing
// video at 0.8 to 1 A this tablet read 7 % at 3.26 V, 4 % at 2.92 V and 3 % at 2.58 V, and then the
// pack's protection cut the power. Android shuts down cleanly only once the level reads 0, so it
// never did. Newer kernels of this tree report 0 themselves in that case (qcom_smbx, "call a pack
// empty when its voltage says so"); this covers the ones that do not, with the same threshold.

#define LOG_TAG "android.hardware.health-service.gtowifi"

#include <dirent.h>

#include <chrono>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/parseint.h>
#include <android-base/strings.h>
#include <android/binder_interface_utils.h>
#include <health-impl/Health.h>
#include <health/utils.h>

using aidl::android::hardware::health::BatteryCapacityLevel;
using aidl::android::hardware::health::BatteryStatus;
using aidl::android::hardware::health::HalHealthLoop;
using aidl::android::hardware::health::Health;
using aidl::android::hardware::health::HealthInfo;

namespace {

constexpr const char* kPowerSupplyDir = "/sys/class/power_supply";
// Used when no battery declares its minimum: the value of this tablet's device tree
constexpr int kDefaultEmptyMillivolts = 3400;
// Rides out the dip of a burst of load; the collapse this guards against took a quarter of an hour
constexpr std::chrono::seconds kEmptyAfter{60};

// voltage_min_design of the first power supply of type Battery, in millivolts
int ReadEmptyMillivolts() {
    std::unique_ptr<DIR, decltype(&closedir)> dir(opendir(kPowerSupplyDir), closedir);
    if (dir) {
        for (dirent* entry; (entry = readdir(dir.get())) != nullptr;) {
            std::string path = std::string(kPowerSupplyDir) + "/" + entry->d_name;
            std::string type, min_uv;
            int value;
            if (!android::base::ReadFileToString(path + "/type", &type) ||
                android::base::Trim(type) != "Battery") {
                continue;
            }
            if (android::base::ReadFileToString(path + "/voltage_min_design", &min_uv) &&
                android::base::ParseInt(android::base::Trim(min_uv), &value, 1000000, 5000000)) {
                return value / 1000;
            }
        }
    }
    return kDefaultEmptyMillivolts;
}

class GtowifiHealth : public Health {
  public:
    GtowifiHealth(std::string_view instance_name, std::unique_ptr<struct healthd_config>&& config)
        : Health(instance_name, std::move(config)), empty_millivolts_(ReadEmptyMillivolts()) {
        LOG(INFO) << "a discharging battery below " << empty_millivolts_ << " mV for "
                  << kEmptyAfter.count() << " s is empty";
    }

    ndk::ScopedAStatus getCapacity(int32_t* out) override {
        auto status = Health::getCapacity(out);
        std::lock_guard<std::mutex> lock(mutex_);
        if (status.isOk() && empty_) *out = 0;
        return status;
    }

  protected:
    void UpdateHealthInfo(HealthInfo* info) override {
        bool powered = info->chargerAcOnline || info->chargerUsbOnline ||
                       info->chargerWirelessOnline || info->chargerDockOnline;
        bool discharging = !powered && info->batteryStatus != BatteryStatus::CHARGING &&
                           info->batteryStatus != BatteryStatus::FULL;
        auto now = std::chrono::steady_clock::now();

        std::lock_guard<std::mutex> lock(mutex_);

        if (!discharging) {
            if (empty_) LOG(INFO) << "charger attached, the battery is no longer called empty";
            empty_ = false;
            low_since_.reset();
            return;
        }

        if (!empty_) {
            int mv = info->batteryVoltageMillivolts;
            if (mv <= 0 || mv >= empty_millivolts_) {
                low_since_.reset();
            } else if (!low_since_) {
                low_since_ = now;
            } else if (now - *low_since_ >= kEmptyAfter) {
                empty_ = true;
                LOG(WARNING) << "battery empty: " << mv << " mV, below " << empty_millivolts_
                             << " mV for " << kEmptyAfter.count() << " s; level "
                             << info->batteryLevel << " % reported as 0";
            }
        }

        if (empty_) {
            info->batteryLevel = 0;
            if (info->batteryCapacityLevel != BatteryCapacityLevel::UNSUPPORTED) {
                info->batteryCapacityLevel = BatteryCapacityLevel::CRITICAL;
            }
        }
    }

  private:
    const int empty_millivolts_;
    std::mutex mutex_;
    bool empty_ = false;
    std::optional<std::chrono::steady_clock::time_point> low_since_;
};

}  // namespace

int main() {
    auto config = std::make_unique<healthd_config>();
    ::android::hardware::health::InitHealthdConfig(config.get());
    auto binder = ndk::SharedRefBase::make<GtowifiHealth>("default", std::move(config));

    // No --charger mode: this device has no off-mode charging (the boot loader boots Android)
    LOG(INFO) << "Starting health HAL.";
    auto hal_health_loop = std::make_shared<HalHealthLoop>(binder, binder);
    return hal_health_loop->StartLoop();
}
