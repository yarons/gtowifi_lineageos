/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

// Holds a CPU latency QoS request for as long as it runs, so that the CPU power domains never reach
// the system power collapse while the system is awake: only in suspend (s2idle ignores the request).
//
// On the SDM429 the system power collapse hands the application processor's sleep to the RPM, which
// then switches the XO off for everything on an active-only vote. Reached from plain runtime idle,
// that stopped the clock of devices still moving data (USB, eMMC, others on the GCC) and the tablet
// reset without a word, minutes to hours after boot. In suspend the same state is what gets the SoC
// to VDD minimisation: about 14 mA asleep against 49 mA without it (SM-T290, kernel r16 line,
// 2026-10-06).
//
// The default, 2000 us, is above the cluster power collapse (exit latency 1000 us), which stays
// available, and below the system power collapse (10800 us). The value is the first argument.

#define LOG_TAG "gtowifi_cpu_latency"

#include <fcntl.h>
#include <unistd.h>

#include <cstdint>
#include <cstdlib>

#include <android-base/logging.h>
#include <android-base/unique_fd.h>

int main(int argc, char** argv) {
    int32_t us = argc > 1 ? atoi(argv[1]) : 2000;

    android::base::unique_fd fd(open("/dev/cpu_dma_latency", O_RDWR | O_CLOEXEC));
    if (fd < 0) {
        PLOG(ERROR) << "open /dev/cpu_dma_latency";
        return EXIT_FAILURE;
    }
    if (write(fd.get(), &us, sizeof(us)) != sizeof(us)) {
        PLOG(ERROR) << "write /dev/cpu_dma_latency";
        return EXIT_FAILURE;
    }
    LOG(INFO) << "holding a CPU latency of " << us << " us";

    // The request lasts while the file stays open
    for (;;) pause();
}
