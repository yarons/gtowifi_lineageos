/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "gnss-qmiloc"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include "Gnss.h"

using aidl::android::hardware::gnss::qmiloc::Gnss;

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(1);
    ABinderProcess_startThreadPool();

    /*
     * The framework waits for this service because the manifest declares it: register first, the
     * modem is only looked for when a session starts.
     */
    std::shared_ptr<Gnss> gnss = ndk::SharedRefBase::make<Gnss>();
    const std::string instance = std::string(Gnss::descriptor) + "/default";
    binder_status_t status = AServiceManager_addService(gnss->asBinder().get(), instance.c_str());
    CHECK_EQ(status, STATUS_OK) << "Failed to register " << instance;

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;
}
