/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "gnss-qmiloc"

#include "QmiLoc.h"

#include <android-base/logging.h>
#include <endian.h>
#include <linux/qrtr.h>
#include <poll.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstring>

#ifndef AF_QIPCRTR
#define AF_QIPCRTR 42
#endif

namespace aidl::android::hardware::gnss::qmiloc {

namespace {

constexpr uint32_t kLocService = 16;

/* QMI over QRTR: type (1), transaction (2), message (2), length (2), then TLVs: type (1), length (2) */
constexpr size_t kHeaderSize = 7;
constexpr uint8_t kTypeRequest = 0;
constexpr uint8_t kTypeResponse = 2;
constexpr uint8_t kTypeIndication = 4;

constexpr uint16_t kMsgRegisterEvents = 0x0021;
constexpr uint16_t kMsgStart = 0x0022;
constexpr uint16_t kMsgStop = 0x0023;
constexpr uint16_t kIndPosition = 0x0024;
constexpr uint16_t kIndSatellites = 0x0025;
constexpr uint16_t kIndNmea = 0x0026;
constexpr uint16_t kMsgInjectUtcTime = 0x0038;

constexpr uint64_t kEventPosition = 0x01;
constexpr uint64_t kEventSatellites = 0x02;
constexpr uint64_t kEventNmea = 0x04;

constexpr uint8_t kSessionId = 1;
constexpr uint32_t kRecurrencePeriodic = 1;
constexpr uint32_t kIntermediateReportsOn = 1;

constexpr size_t kSatelliteSize = 28;

uint64_t bootTimeMs() {
    timespec ts{};
    clock_gettime(CLOCK_BOOTTIME, &ts);
    return static_cast<uint64_t>(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

/* The modem is little endian and so is every Android device this can run on */
template <typename T>
void addTlv(std::vector<uint8_t>* tlvs, uint8_t type, T value) {
    const uint8_t* bytes = reinterpret_cast<const uint8_t*>(&value);
    tlvs->push_back(type);
    tlvs->push_back(sizeof(T) & 0xff);
    tlvs->push_back(sizeof(T) >> 8);
    tlvs->insert(tlvs->end(), bytes, bytes + sizeof(T));
}

template <typename T>
bool readValue(const uint8_t* data, size_t size, T* value) {
    if (size < sizeof(T)) return false;
    memcpy(value, data, sizeof(T));
    return true;
}

/* Calls handler(type, data, size) for every complete TLV */
template <typename Handler>
void forEachTlv(const uint8_t* data, size_t size, Handler handler) {
    while (size >= 3) {
        const size_t length = data[1] | (data[2] << 8);
        if (3 + length > size) break;
        handler(data[0], data + 3, length);
        data += 3 + length;
        size -= 3 + length;
    }
}

/* Ask the QRTR name service of this node where the location service lives */
bool findService(int fd, sockaddr_qrtr* service) {
    sockaddr_qrtr self{};
    socklen_t length = sizeof(self);
    if (getsockname(fd, reinterpret_cast<sockaddr*>(&self), &length) < 0) {
        PLOG(ERROR) << "getsockname";
        return false;
    }

    qrtr_ctrl_pkt lookup{};
    lookup.cmd = htole32(QRTR_TYPE_NEW_LOOKUP);
    lookup.server.service = htole32(kLocService);
    sockaddr_qrtr control{};
    control.sq_family = AF_QIPCRTR;
    control.sq_node = self.sq_node;
    control.sq_port = QRTR_PORT_CTRL;
    if (sendto(fd, &lookup, sizeof(lookup), 0, reinterpret_cast<sockaddr*>(&control),
               sizeof(control)) < 0) {
        PLOG(ERROR) << "QRTR lookup";
        return false;
    }

    /* The known servers follow, then an empty entry; later changes arrive as they happen */
    bool found = false;
    for (;;) {
        pollfd fds = {fd, POLLIN, 0};
        if (poll(&fds, 1, 2000) <= 0) break;

        qrtr_ctrl_pkt reply{};
        sockaddr_qrtr from{};
        socklen_t fromLength = sizeof(from);
        ssize_t received = recvfrom(fd, &reply, sizeof(reply), 0,
                                    reinterpret_cast<sockaddr*>(&from), &fromLength);
        if (received < 0) break;
        if (received < static_cast<ssize_t>(sizeof(reply)) || from.sq_port != QRTR_PORT_CTRL ||
            le32toh(reply.cmd) != QRTR_TYPE_NEW_SERVER)
            continue;
        if (!reply.server.service && !reply.server.instance && !reply.server.node &&
            !reply.server.port)
            break;
        if (le32toh(reply.server.service) != kLocService || found) continue;

        service->sq_family = AF_QIPCRTR;
        service->sq_node = le32toh(reply.server.node);
        service->sq_port = le32toh(reply.server.port);
        found = true;
        LOG(INFO) << "Location service v" << (le32toh(reply.server.instance) & 0xff) << " at "
                  << service->sq_node << ":" << service->sq_port;
    }

    return found;
}

void parsePosition(const uint8_t* data, size_t size, LocPosition* position) {
    forEachTlv(data, size, [position](uint8_t type, const uint8_t* value, size_t length) {
        switch (type) {
            case 0x01:
                readValue(value, length, &position->status);
                break;
            case 0x10:
                if (readValue(value, length, &position->latitude))
                    position->has |= LocPosition::HAS_LAT_LONG;
                break;
            case 0x11:
                readValue(value, length, &position->longitude);
                break;
            case 0x12:
                if (readValue(value, length, &position->horizontalUnc))
                    position->has |= LocPosition::HAS_HORIZONTAL_UNC;
                break;
            case 0x18:
                if (readValue(value, length, &position->speed))
                    position->has |= LocPosition::HAS_SPEED;
                break;
            case 0x19:
                if (readValue(value, length, &position->speedUnc))
                    position->has |= LocPosition::HAS_SPEED_UNC;
                break;
            case 0x1a:
                if (readValue(value, length, &position->altitudeEllipsoid))
                    position->has |= LocPosition::HAS_ALTITUDE;
                break;
            case 0x1c:
                if (readValue(value, length, &position->verticalUnc))
                    position->has |= LocPosition::HAS_VERTICAL_UNC;
                break;
            case 0x20:
                if (readValue(value, length, &position->heading))
                    position->has |= LocPosition::HAS_HEADING;
                break;
            case 0x21:
                if (readValue(value, length, &position->headingUnc))
                    position->has |= LocPosition::HAS_HEADING_UNC;
                break;
            case 0x25:
                if (readValue(value, length, &position->utcMs))
                    position->has |= LocPosition::HAS_UTC;
                break;
            case 0x2c:
                if (length >= 1 && length >= 1 + 2u * value[0]) {
                    for (size_t i = 0; i < value[0]; i++) {
                        uint16_t id;
                        memcpy(&id, value + 1 + 2 * i, sizeof(id));
                        position->svUsed.push_back(id);
                    }
                }
                break;
        }
    });
}

void parseSatellites(const uint8_t* data, size_t size, std::vector<LocSv>* satellites) {
    forEachTlv(data, size, [satellites](uint8_t type, const uint8_t* value, size_t length) {
        if (type != 0x10 || length < 1 || length < 1 + kSatelliteSize * value[0]) return;

        for (size_t i = 0; i < value[0]; i++) {
            const uint8_t* element = value + 1 + kSatelliteSize * i;
            LocSv sv;
            memcpy(&sv.valid, element, 4);
            memcpy(&sv.system, element + 4, 4);
            memcpy(&sv.id, element + 8, 2);
            sv.health = element[10];
            memcpy(&sv.status, element + 11, 4);
            sv.navData = element[15];
            memcpy(&sv.elevation, element + 16, 4);
            memcpy(&sv.azimuth, element + 20, 4);
            memcpy(&sv.snr, element + 24, 4);
            satellites->push_back(sv);
        }
    });
}

}  // namespace

QmiLoc::QmiLoc(QmiLocListener* listener) : mListener(listener) {
    mWakeFd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (mWakeFd < 0) PLOG(FATAL) << "eventfd";
    mThread = std::thread(&QmiLoc::threadLoop, this);
}

QmiLoc::~QmiLoc() {
    {
        std::lock_guard<std::mutex> lock(mLock);
        mExit = true;
    }
    wake();
    mThread.join();
    close(mWakeFd);
}

void QmiLoc::start(uint32_t minIntervalMs) {
    {
        std::lock_guard<std::mutex> lock(mLock);
        if (mWanted && minIntervalMs != mMinIntervalMs) mRestart = true;
        mWanted = true;
        mMinIntervalMs = minIntervalMs;
    }
    wake();
}

void QmiLoc::stop() {
    {
        std::lock_guard<std::mutex> lock(mLock);
        mWanted = false;
    }
    wake();
}

void QmiLoc::injectTime(uint64_t utcMs, uint32_t uncertaintyMs) {
    {
        std::lock_guard<std::mutex> lock(mLock);
        mTimePending = true;
        mTimeUtcMs = utcMs;
        mTimeReferenceMs = bootTimeMs();
        mTimeUncertaintyMs = uncertaintyMs;
    }
    wake();
}

void QmiLoc::wake() {
    uint64_t one = 1;
    if (write(mWakeFd, &one, sizeof(one)) < 0 && errno != EAGAIN) PLOG(ERROR) << "eventfd";
    mCondition.notify_all();
}

void QmiLoc::threadLoop() {
    for (;;) {
        {
            std::unique_lock<std::mutex> lock(mLock);
            mCondition.wait(lock, [this] { return mExit || mWanted; });
            if (mExit) return;
        }

        bool finished = false;
        int fd = socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0);
        if (fd < 0) {
            PLOG(ERROR) << "QRTR socket";
        } else {
            sockaddr_qrtr service{};
            if (findService(fd, &service)) {
                finished = runSession(fd, service);
                mListener->onSession(false);
            } else {
                LOG(WARNING) << "No location service on QRTR: is the modem running?";
            }
            /* Closing the socket ends the session in the modem, whatever state it is in */
            close(fd);
        }

        if (!finished) {
            std::unique_lock<std::mutex> lock(mLock);
            mCondition.wait_for(lock, std::chrono::seconds(5),
                                [this] { return mExit || !mWanted; });
        }
    }
}

bool QmiLoc::request(int fd, const sockaddr_qrtr& service, uint16_t message,
                     const std::vector<uint8_t>& tlvs) {
    std::vector<uint8_t> packet(kHeaderSize);
    mTransaction++;
    packet[0] = kTypeRequest;
    packet[1] = mTransaction & 0xff;
    packet[2] = mTransaction >> 8;
    packet[3] = message & 0xff;
    packet[4] = message >> 8;
    packet[5] = tlvs.size() & 0xff;
    packet[6] = tlvs.size() >> 8;
    packet.insert(packet.end(), tlvs.begin(), tlvs.end());

    if (sendto(fd, packet.data(), packet.size(), 0, reinterpret_cast<const sockaddr*>(&service),
               sizeof(service)) < 0) {
        PLOG(ERROR) << "Request 0x" << std::hex << message;
        return false;
    }
    return true;
}

bool QmiLoc::runSession(int fd, const sockaddr_qrtr& service) {
    auto startSession = [&]() {
        uint32_t interval;
        {
            std::lock_guard<std::mutex> lock(mLock);
            interval = mMinIntervalMs;
            mRestart = false;
        }
        std::vector<uint8_t> tlvs;
        addTlv<uint8_t>(&tlvs, 0x01, kSessionId);
        addTlv<uint32_t>(&tlvs, 0x10, kRecurrencePeriodic);
        addTlv<uint32_t>(&tlvs, 0x12, kIntermediateReportsOn);
        addTlv<uint32_t>(&tlvs, 0x13, interval);
        LOG(INFO) << "Starting a periodic session, " << interval << " ms";
        return request(fd, service, kMsgStart, tlvs);
    };
    auto stopSession = [&]() {
        std::vector<uint8_t> tlvs;
        addTlv<uint8_t>(&tlvs, 0x01, kSessionId);
        return request(fd, service, kMsgStop, tlvs);
    };
    auto sendTime = [&]() {
        uint64_t utcMs;
        uint32_t uncertaintyMs;
        {
            std::lock_guard<std::mutex> lock(mLock);
            if (!mTimePending) return true;
            mTimePending = false;
            utcMs = mTimeUtcMs + (bootTimeMs() - mTimeReferenceMs);
            uncertaintyMs = mTimeUncertaintyMs;
        }
        std::vector<uint8_t> tlvs;
        addTlv<uint64_t>(&tlvs, 0x01, utcMs);
        addTlv<uint32_t>(&tlvs, 0x02, uncertaintyMs);
        return request(fd, service, kMsgInjectUtcTime, tlvs);
    };

    std::vector<uint8_t> events;
    addTlv<uint64_t>(&events, 0x01, kEventPosition | kEventSatellites | kEventNmea);
    if (!request(fd, service, kMsgRegisterEvents, events) || !sendTime() || !startSession())
        return false;
    mListener->onSession(true);

    std::vector<uint8_t> buffer(4096);
    for (;;) {
        pollfd fds[2] = {{fd, POLLIN, 0}, {mWakeFd, POLLIN, 0}};
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR) continue;
            PLOG(ERROR) << "poll";
            return false;
        }

        if (fds[1].revents & POLLIN) {
            uint64_t count;
            if (read(mWakeFd, &count, sizeof(count)) < 0 && errno != EAGAIN) PLOG(ERROR) << "eventfd";

            bool wanted, restart;
            {
                std::lock_guard<std::mutex> lock(mLock);
                wanted = mWanted && !mExit;
                restart = mRestart;
            }
            if (!wanted) {
                stopSession();
                return true;
            }
            if (restart && (!stopSession() || !startSession())) return false;
            if (!sendTime()) return false;
        }

        if (fds[0].revents & (POLLERR | POLLHUP)) {
            LOG(WARNING) << "QRTR socket error, the modem may have restarted";
            return false;
        }
        if (!(fds[0].revents & POLLIN)) continue;

        sockaddr_qrtr from{};
        socklen_t fromLength = sizeof(from);
        ssize_t received = recvfrom(fd, buffer.data(), buffer.size(), 0,
                                    reinterpret_cast<sockaddr*>(&from), &fromLength);
        if (received < 0) {
            if (errno == EINTR || errno == EAGAIN) continue;
            PLOG(WARNING) << "QRTR receive";
            return false;
        }

        if (from.sq_port == QRTR_PORT_CTRL) {
            /* The lookup is still registered: this is how the death of the modem shows */
            qrtr_ctrl_pkt packet{};
            if (received >= static_cast<ssize_t>(sizeof(packet))) {
                memcpy(&packet, buffer.data(), sizeof(packet));
                if (le32toh(packet.cmd) == QRTR_TYPE_DEL_SERVER &&
                    le32toh(packet.server.node) == service.sq_node &&
                    le32toh(packet.server.port) == service.sq_port) {
                    LOG(WARNING) << "The location service went away";
                    return false;
                }
            }
            continue;
        }

        if (from.sq_node == service.sq_node && from.sq_port == service.sq_port)
            handleMessage(buffer.data(), received);
    }
}

void QmiLoc::handleMessage(const uint8_t* data, size_t size) {
    if (size < kHeaderSize) return;

    const uint8_t type = data[0];
    const uint16_t message = data[3] | (data[4] << 8);
    size_t length = data[5] | (data[6] << 8);
    if (length > size - kHeaderSize) length = size - kHeaderSize;
    data += kHeaderSize;

    if (type == kTypeResponse) {
        /* Result TLV: result (0 success), error */
        forEachTlv(data, length, [message](uint8_t tlv, const uint8_t* value, size_t valueLength) {
            uint16_t result[2];
            if (tlv != 0x02 || !readValue(value, valueLength, &result)) return;
            if (result[0])
                LOG(ERROR) << "Request 0x" << std::hex << message << " failed, error 0x" << result[1];
        });
        return;
    }
    if (type != kTypeIndication) return;

    switch (message) {
        case kIndPosition: {
            LocPosition position;
            parsePosition(data, length, &position);
            mListener->onPosition(position);
            break;
        }
        case kIndSatellites: {
            std::vector<LocSv> satellites;
            parseSatellites(data, length, &satellites);
            mListener->onSatellites(satellites);
            break;
        }
        case kIndNmea:
            forEachTlv(data, length, [this](uint8_t tlv, const uint8_t* value, size_t valueLength) {
                if (tlv != 0x01) return;
                std::string sentence(reinterpret_cast<const char*>(value), valueLength);
                while (!sentence.empty() && sentence.back() == '\0') sentence.pop_back();
                if (!sentence.empty()) mListener->onNmea(sentence);
            });
            break;
    }
}

}  // namespace aidl::android::hardware::gnss::qmiloc
