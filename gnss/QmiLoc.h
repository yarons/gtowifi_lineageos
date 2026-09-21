/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct sockaddr_qrtr;

namespace aidl::android::hardware::gnss::qmiloc {

/* Position report indication (0x0024). "has" is a mask of the fields the modem sent. */
struct LocPosition {
    enum : uint32_t {
        HAS_LAT_LONG = 1 << 0,
        HAS_ALTITUDE = 1 << 1,
        HAS_SPEED = 1 << 2,
        HAS_HEADING = 1 << 3,
        HAS_HORIZONTAL_UNC = 1 << 4,
        HAS_VERTICAL_UNC = 1 << 5,
        HAS_SPEED_UNC = 1 << 6,
        HAS_HEADING_UNC = 1 << 7,
        HAS_UTC = 1 << 8,
    };

    /* 0 fix, 1 session in progress (intermediate report), 2 failure, 3 timeout, ... */
    uint32_t status = ~0u;
    uint32_t has = 0;
    double latitude = 0;
    double longitude = 0;
    float altitudeEllipsoid = 0;
    float speed = 0;
    float heading = 0;
    float horizontalUnc = 0;
    float verticalUnc = 0;
    float speedUnc = 0;
    float headingUnc = 0;
    uint64_t utcMs = 0;
    /* Satellites used for the fix, in the numbering of the modem */
    std::vector<uint16_t> svUsed;
};

/* One element of the satellite report indication (0x0025) */
struct LocSv {
    enum : uint32_t {
        VALID_SYSTEM = 0x01,
        VALID_ID = 0x02,
        VALID_HEALTH = 0x04,
        VALID_STATUS = 0x08,
        VALID_NAV_DATA = 0x10,
        VALID_ELEVATION = 0x20,
        VALID_AZIMUTH = 0x40,
        VALID_SNR = 0x80,
    };
    enum : uint32_t { SYSTEM_GPS = 1, SYSTEM_GALILEO, SYSTEM_SBAS, SYSTEM_COMPASS, SYSTEM_GLONASS,
                      SYSTEM_BDS, SYSTEM_QZSS };
    enum : uint32_t { STATUS_IDLE = 1, STATUS_SEARCH, STATUS_TRACK };
    enum : uint8_t { NAV_EPHEMERIS = 0x01, NAV_ALMANAC = 0x02 };

    uint32_t valid = 0;
    uint32_t system = 0;
    uint16_t id = 0;
    uint8_t health = 0;
    uint32_t status = 0;
    uint8_t navData = 0;
    float elevation = 0;
    float azimuth = 0;
    float snr = 0;
};

class QmiLocListener {
  public:
    virtual ~QmiLocListener() = default;
    /* The location service of the modem was found and a session started (true), or it went away */
    virtual void onSession(bool running) = 0;
    virtual void onPosition(const LocPosition& position) = 0;
    virtual void onSatellites(const std::vector<LocSv>& satellites) = 0;
    virtual void onNmea(const std::string& sentence) = 0;
};

/*
 * Client of the QMI location service (LOC, service 16) of a Qualcomm modem, over QRTR.
 *
 * A session belongs to the socket that started it and ends with it, so one thread owns the socket
 * for as long as a session is wanted, and everything that is sent goes through that thread.
 */
class QmiLoc {
  public:
    explicit QmiLoc(QmiLocListener* listener);
    ~QmiLoc();

    /* Want a periodic session; called again with another interval it restarts the session */
    void start(uint32_t minIntervalMs);
    void stop();
    /* Tell the engine the time. Only possible while a session runs; dropped otherwise */
    void injectTime(uint64_t utcMs, uint32_t uncertaintyMs);

  private:
    void threadLoop();
    /* Returns when the session is not wanted any more (true) or the service went away (false) */
    bool runSession(int fd, const sockaddr_qrtr& service);
    bool request(int fd, const sockaddr_qrtr& service, uint16_t message,
                 const std::vector<uint8_t>& tlvs);
    void handleMessage(const uint8_t* data, size_t size);
    void wake();

    QmiLocListener* const mListener;

    std::mutex mLock;
    std::condition_variable mCondition;
    bool mExit = false;
    bool mWanted = false;
    bool mRestart = false;
    uint32_t mMinIntervalMs = 1000;
    bool mTimePending = false;
    uint64_t mTimeUtcMs = 0;
    uint64_t mTimeReferenceMs = 0;
    uint32_t mTimeUncertaintyMs = 0;

    int mWakeFd = -1;
    uint16_t mTransaction = 0;
    std::thread mThread;
};

}  // namespace aidl::android::hardware::gnss::qmiloc
