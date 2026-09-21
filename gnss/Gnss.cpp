/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "gnss-qmiloc"

#include "Gnss.h"

#include <android-base/logging.h>
#include <utils/SystemClock.h>

#include <algorithm>
#include <chrono>

namespace aidl::android::hardware::gnss::qmiloc {

namespace {

using GnssSvInfo = IGnssCallback::GnssSvInfo;
using GnssSvFlags = IGnssCallback::GnssSvFlags;
using GnssStatusValue = IGnssCallback::GnssStatusValue;

constexpr uint32_t kShortestIntervalMs = 1000;

ndk::ScopedAStatus unsupported() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

void logIfFailed(const ndk::ScopedAStatus& status, const char* what) {
    if (!status.isOk()) LOG(WARNING) << what << ": " << status.getDescription();
}

/*
 * The modem numbers the satellites of all systems in one range, Android per constellation.
 * Carrier frequencies: the engine is a single band (L1/E1/B1/G1) one; GLONASS is the centre of its
 * band because the report lacks the frequency channel.
 */
bool convertSatellite(const LocSv& sv, GnssSvInfo* info) {
    if (!(sv.valid & LocSv::VALID_SYSTEM) || !(sv.valid & LocSv::VALID_ID)) return false;

    int first, last, offset;
    switch (sv.system) {
        case LocSv::SYSTEM_GPS:
            info->constellation = GnssConstellationType::GPS;
            info->carrierFrequencyHz = 1575420000;
            first = 1, last = 32, offset = 0;
            break;
        case LocSv::SYSTEM_SBAS:
            info->constellation = GnssConstellationType::SBAS;
            info->carrierFrequencyHz = 1575420000;
            first = 33, last = 64, offset = 87;
            break;
        case LocSv::SYSTEM_GLONASS:
            info->constellation = GnssConstellationType::GLONASS;
            info->carrierFrequencyHz = 1602000000;
            first = 65, last = 96, offset = -64;
            break;
        case LocSv::SYSTEM_QZSS:
            info->constellation = GnssConstellationType::QZSS;
            info->carrierFrequencyHz = 1575420000;
            first = 193, last = 200, offset = 0;
            break;
        case LocSv::SYSTEM_COMPASS:
        case LocSv::SYSTEM_BDS:
            info->constellation = GnssConstellationType::BEIDOU;
            info->carrierFrequencyHz = 1561098000;
            first = 201, last = 263, offset = -200;
            break;
        case LocSv::SYSTEM_GALILEO:
            info->constellation = GnssConstellationType::GALILEO;
            info->carrierFrequencyHz = 1575420000;
            first = 301, last = 336, offset = -300;
            break;
        default:
            return false;
    }
    if (sv.id < first || sv.id > last) return false;
    info->svid = sv.id + offset;

    const bool tracked = (sv.valid & LocSv::VALID_STATUS) && sv.status == LocSv::STATUS_TRACK;
    info->cN0Dbhz = tracked && (sv.valid & LocSv::VALID_SNR) ? sv.snr : 0;
    info->basebandCN0DbHz = info->cN0Dbhz;
    info->elevationDegrees = sv.valid & LocSv::VALID_ELEVATION ? sv.elevation : 0;
    info->azimuthDegrees = sv.valid & LocSv::VALID_AZIMUTH ? sv.azimuth : 0;

    info->svFlag = static_cast<int>(GnssSvFlags::HAS_CARRIER_FREQUENCY);
    if (sv.valid & LocSv::VALID_NAV_DATA) {
        if (sv.navData & LocSv::NAV_EPHEMERIS)
            info->svFlag |= static_cast<int>(GnssSvFlags::HAS_EPHEMERIS_DATA);
        if (sv.navData & LocSv::NAV_ALMANAC)
            info->svFlag |= static_cast<int>(GnssSvFlags::HAS_ALMANAC_DATA);
    }
    return true;
}

}  // namespace

Gnss::Gnss() : mLoc(this) {}

std::shared_ptr<IGnssCallback> Gnss::callback() {
    std::lock_guard<std::mutex> lock(mLock);
    return mCallback;
}

ndk::ScopedAStatus Gnss::setCallback(const std::shared_ptr<IGnssCallback>& callback) {
    if (!callback) return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    {
        std::lock_guard<std::mutex> lock(mLock);
        mCallback = callback;
    }

    /* The engine schedules its periodic fixes itself and can use the time of the system */
    logIfFailed(callback->gnssSetCapabilitiesCb(IGnssCallback::CAPABILITY_SCHEDULING |
                                                IGnssCallback::CAPABILITY_ON_DEMAND_TIME),
                "gnssSetCapabilitiesCb");
    IGnssCallback::GnssSystemInfo info;
    /* Hardware of 2016 and later has to deliver raw measurements, which this HAL does not */
    info.yearOfHw = 2015;
    info.name = "Qualcomm location engine, QMI LOC over QRTR";
    logIfFailed(callback->gnssSetSystemInfoCb(info), "gnssSetSystemInfoCb");
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::close() {
    mLoc.stop();
    std::lock_guard<std::mutex> lock(mLock);
    mStarted = false;
    mCallback = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::start() {
    uint32_t interval;
    {
        std::lock_guard<std::mutex> lock(mLock);
        mStarted = true;
        mUsedInFix.clear();
        interval = mMinIntervalMs;
    }
    mLoc.start(interval);
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::stop() {
    {
        std::lock_guard<std::mutex> lock(mLock);
        mStarted = false;
    }
    mLoc.stop();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::injectTime(int64_t timeMs, int64_t timeReferenceMs,
                                    int32_t uncertaintyMs) {
    /* timeMs was right when the time since boot was timeReferenceMs */
    const int64_t now = timeMs + (::android::elapsedRealtime() - timeReferenceMs);
    if (now > 0) mLoc.injectTime(now, std::max(uncertaintyMs, 0));
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::injectLocation(const GnssLocation&) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::injectBestLocation(const GnssLocation&) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::deleteAidingData(GnssAidingData) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::setPositionMode(const PositionModeOptions& options) {
    bool started;
    uint32_t interval = std::max<int64_t>(options.minIntervalMs, kShortestIntervalMs);
    {
        std::lock_guard<std::mutex> lock(mLock);
        mMinIntervalMs = interval;
        started = mStarted;
    }
    /* A running session is started again if the interval is another one */
    if (started) mLoc.start(interval);
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::startSvStatus() {
    std::lock_guard<std::mutex> lock(mLock);
    mSvStatus = true;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::stopSvStatus() {
    std::lock_guard<std::mutex> lock(mLock);
    mSvStatus = false;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::startNmea() {
    std::lock_guard<std::mutex> lock(mLock);
    mNmea = true;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::stopNmea() {
    std::lock_guard<std::mutex> lock(mLock);
    mNmea = false;
    return ndk::ScopedAStatus::ok();
}

/* The framework copes with every missing extension: null where that is allowed, an error elsewhere */
ndk::ScopedAStatus Gnss::getExtensionPsds(std::shared_ptr<IGnssPsds>* result) {
    *result = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssBatching(std::shared_ptr<IGnssBatching>* result) {
    *result = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssGeofence(std::shared_ptr<IGnssGeofence>* result) {
    *result = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssNavigationMessage(
        std::shared_ptr<IGnssNavigationMessageInterface>* result) {
    *result = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionMeasurementCorrections(
        std::shared_ptr<measurement_corrections::IMeasurementCorrectionsInterface>* result) {
    *result = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssConfiguration(std::shared_ptr<IGnssConfiguration>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionGnssMeasurement(std::shared_ptr<IGnssMeasurementInterface>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionGnssPowerIndication(std::shared_ptr<IGnssPowerIndication>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionAGnss(std::shared_ptr<IAGnss>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionAGnssRil(std::shared_ptr<IAGnssRil>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionGnssDebug(std::shared_ptr<IGnssDebug>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionGnssVisibilityControl(
        std::shared_ptr<visibility_control::IGnssVisibilityControl>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionGnssAntennaInfo(std::shared_ptr<IGnssAntennaInfo>*) {
    return unsupported();
}

ndk::ScopedAStatus Gnss::getExtensionGnssAssistanceInterface(
        std::shared_ptr<gnss_assistance::IGnssAssistanceInterface>*) {
    return unsupported();
}

void Gnss::onSession(bool running) {
    auto cb = callback();
    if (!cb) return;

    if (running) {
        logIfFailed(cb->gnssStatusCb(GnssStatusValue::ENGINE_ON), "gnssStatusCb");
        logIfFailed(cb->gnssStatusCb(GnssStatusValue::SESSION_BEGIN), "gnssStatusCb");
        /* Cold starts are faster when the engine knows the time */
        logIfFailed(cb->gnssRequestTimeCb(), "gnssRequestTimeCb");
    } else {
        logIfFailed(cb->gnssStatusCb(GnssStatusValue::SESSION_END), "gnssStatusCb");
        logIfFailed(cb->gnssStatusCb(GnssStatusValue::ENGINE_OFF), "gnssStatusCb");
    }
}

void Gnss::onPosition(const LocPosition& position) {
    /* Status 0 is a fix; intermediate reports (1) and timeouts (3) are not for applications */
    if (position.status != 0 || !(position.has & LocPosition::HAS_LAT_LONG)) return;

    std::shared_ptr<IGnssCallback> cb;
    {
        std::lock_guard<std::mutex> lock(mLock);
        mUsedInFix = std::set<uint16_t>(position.svUsed.begin(), position.svUsed.end());
        if (!mStarted) return;
        cb = mCallback;
    }
    if (!cb) return;

    GnssLocation location{};
    location.gnssLocationFlags = GnssLocation::HAS_LAT_LONG;
    location.latitudeDegrees = position.latitude;
    location.longitudeDegrees = position.longitude;
    if (position.has & LocPosition::HAS_ALTITUDE) {
        location.gnssLocationFlags |= GnssLocation::HAS_ALTITUDE;
        location.altitudeMeters = position.altitudeEllipsoid;
    }
    if (position.has & LocPosition::HAS_SPEED) {
        location.gnssLocationFlags |= GnssLocation::HAS_SPEED;
        location.speedMetersPerSec = position.speed;
    }
    if (position.has & LocPosition::HAS_HEADING) {
        location.gnssLocationFlags |= GnssLocation::HAS_BEARING;
        location.bearingDegrees = position.heading;
    }
    /* Circular uncertainty at the confidence of the modem, close enough to Android's 68 % */
    if (position.has & LocPosition::HAS_HORIZONTAL_UNC) {
        location.gnssLocationFlags |= GnssLocation::HAS_HORIZONTAL_ACCURACY;
        location.horizontalAccuracyMeters = position.horizontalUnc;
    }
    if (position.has & LocPosition::HAS_VERTICAL_UNC) {
        location.gnssLocationFlags |= GnssLocation::HAS_VERTICAL_ACCURACY;
        location.verticalAccuracyMeters = position.verticalUnc;
    }
    if (position.has & LocPosition::HAS_SPEED_UNC) {
        location.gnssLocationFlags |= GnssLocation::HAS_SPEED_ACCURACY;
        location.speedAccuracyMetersPerSecond = position.speedUnc;
    }
    if (position.has & LocPosition::HAS_HEADING_UNC) {
        location.gnssLocationFlags |= GnssLocation::HAS_BEARING_ACCURACY;
        location.bearingAccuracyDegrees = position.headingUnc;
    }
    if (position.has & LocPosition::HAS_UTC) {
        location.timestampMillis = position.utcMs;
    } else {
        location.timestampMillis = std::chrono::duration_cast<std::chrono::milliseconds>(
                                           std::chrono::system_clock::now().time_since_epoch())
                                           .count();
    }
    location.elapsedRealtime.flags =
            ElapsedRealtime::HAS_TIMESTAMP_NS | ElapsedRealtime::HAS_TIME_UNCERTAINTY_NS;
    location.elapsedRealtime.timestampNs = ::android::elapsedRealtimeNano();
    /* The report is a few milliseconds old when it arrives here */
    location.elapsedRealtime.timeUncertaintyNs = 10000000;

    logIfFailed(cb->gnssLocationCb(location), "gnssLocationCb");
}

void Gnss::onSatellites(const std::vector<LocSv>& satellites) {
    std::shared_ptr<IGnssCallback> cb;
    std::set<uint16_t> used;
    {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStarted || !mSvStatus) return;
        cb = mCallback;
        used = mUsedInFix;
    }
    if (!cb) return;

    std::vector<GnssSvInfo> list;
    for (const LocSv& sv : satellites) {
        GnssSvInfo info{};
        if (!convertSatellite(sv, &info)) continue;
        if (used.count(sv.id)) info.svFlag |= static_cast<int>(GnssSvFlags::USED_IN_FIX);
        list.push_back(info);
    }
    logIfFailed(cb->gnssSvStatusCb(list), "gnssSvStatusCb");
}

void Gnss::onNmea(const std::string& sentence) {
    std::shared_ptr<IGnssCallback> cb;
    {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStarted || !mNmea) return;
        cb = mCallback;
    }
    if (!cb) return;

    const int64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::system_clock::now().time_since_epoch())
                                .count();
    logIfFailed(cb->gnssNmeaCb(now, sentence), "gnssNmeaCb");
}

}  // namespace aidl::android::hardware::gnss::qmiloc
