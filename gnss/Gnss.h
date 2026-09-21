/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <aidl/android/hardware/gnss/BnGnss.h>

#include <memory>
#include <mutex>
#include <set>

#include "QmiLoc.h"

namespace aidl::android::hardware::gnss::qmiloc {

/*
 * Positions, satellites and NMEA from the location engine of the modem. None of the optional
 * interfaces: no assistance data, no raw measurements, no geofences, no batching.
 */
class Gnss : public BnGnss, public QmiLocListener {
  public:
    Gnss();

    ndk::ScopedAStatus setCallback(const std::shared_ptr<IGnssCallback>& callback) override;
    ndk::ScopedAStatus close() override;
    ndk::ScopedAStatus start() override;
    ndk::ScopedAStatus stop() override;
    ndk::ScopedAStatus injectTime(int64_t timeMs, int64_t timeReferenceMs,
                                  int32_t uncertaintyMs) override;
    ndk::ScopedAStatus injectLocation(const GnssLocation& location) override;
    ndk::ScopedAStatus injectBestLocation(const GnssLocation& location) override;
    ndk::ScopedAStatus deleteAidingData(GnssAidingData aidingDataFlags) override;
    ndk::ScopedAStatus setPositionMode(const PositionModeOptions& options) override;
    ndk::ScopedAStatus startSvStatus() override;
    ndk::ScopedAStatus stopSvStatus() override;
    ndk::ScopedAStatus startNmea() override;
    ndk::ScopedAStatus stopNmea() override;

    ndk::ScopedAStatus getExtensionPsds(std::shared_ptr<IGnssPsds>* result) override;
    ndk::ScopedAStatus getExtensionGnssConfiguration(
            std::shared_ptr<IGnssConfiguration>* result) override;
    ndk::ScopedAStatus getExtensionGnssMeasurement(
            std::shared_ptr<IGnssMeasurementInterface>* result) override;
    ndk::ScopedAStatus getExtensionGnssPowerIndication(
            std::shared_ptr<IGnssPowerIndication>* result) override;
    ndk::ScopedAStatus getExtensionGnssBatching(std::shared_ptr<IGnssBatching>* result) override;
    ndk::ScopedAStatus getExtensionGnssGeofence(std::shared_ptr<IGnssGeofence>* result) override;
    ndk::ScopedAStatus getExtensionGnssNavigationMessage(
            std::shared_ptr<IGnssNavigationMessageInterface>* result) override;
    ndk::ScopedAStatus getExtensionAGnss(std::shared_ptr<IAGnss>* result) override;
    ndk::ScopedAStatus getExtensionAGnssRil(std::shared_ptr<IAGnssRil>* result) override;
    ndk::ScopedAStatus getExtensionGnssDebug(std::shared_ptr<IGnssDebug>* result) override;
    ndk::ScopedAStatus getExtensionGnssVisibilityControl(
            std::shared_ptr<visibility_control::IGnssVisibilityControl>* result) override;
    ndk::ScopedAStatus getExtensionGnssAntennaInfo(
            std::shared_ptr<IGnssAntennaInfo>* result) override;
    ndk::ScopedAStatus getExtensionMeasurementCorrections(
            std::shared_ptr<measurement_corrections::IMeasurementCorrectionsInterface>* result)
            override;
    ndk::ScopedAStatus getExtensionGnssAssistanceInterface(
            std::shared_ptr<gnss_assistance::IGnssAssistanceInterface>* result) override;

    void onSession(bool running) override;
    void onPosition(const LocPosition& position) override;
    void onSatellites(const std::vector<LocSv>& satellites) override;
    void onNmea(const std::string& sentence) override;

  private:
    std::shared_ptr<IGnssCallback> callback();

    std::mutex mLock;
    std::shared_ptr<IGnssCallback> mCallback;
    bool mStarted = false;
    bool mSvStatus = true;
    bool mNmea = false;
    uint32_t mMinIntervalMs = 1000;
    /* Satellites of the last fix, in the numbering of the modem */
    std::set<uint16_t> mUsedInFix;

    /* Last: its thread calls back into this object and has to stop first */
    QmiLoc mLoc;
};

}  // namespace aidl::android::hardware::gnss::qmiloc
