// Copyright 2026 Cua AI, Inc.
// Modifications copyright 2026 Lunchpail contributors.
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>

#include <errno.h>
#include <stdlib.h>

typedef unsigned long long LunchpailU64;

typedef struct {
    BOOL enabled;
    NSUInteger appleFamilyMax;
    NSUInteger maxThreadgroupMemory;
    BOOL hasRecommendedWorkingSetSize;
    NSUInteger recommendedWorkingSetSize;
} LunchpailMetalConfiguration;

static LunchpailMetalConfiguration gConfiguration = {0};
static IMP gOriginalInitGPUFamilySupport = NULL;
static IMP gOriginalMaxThreadgroupMemoryLength = NULL;
static IMP gOriginalRecommendedMaxWorkingSetSize = NULL;
static IMP gOriginalSupportsFamily = NULL;
static BOOL gDeviceHooksInstalled = NO;

static BOOL parseUnsignedEnvironmentValue(const char *name, LunchpailU64 *value) {
    const char *rawValue = getenv(name);
    if (!rawValue || !*rawValue) return NO;

    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(rawValue, &end, 0);
    if (errno != 0 || end == rawValue || !end || *end != '\0') return NO;

    *value = parsed;
    return YES;
}

static BOOL loadConfiguration(void) {
    LunchpailU64 appleFamilyMax = 0;
    if (!parseUnsignedEnvironmentValue(
            "LUNCHPAIL_METAL_APPLE_FAMILY_MAX",
            &appleFamilyMax
        ) || appleFamilyMax < 1001 || appleFamilyMax > 1010) {
        return NO;
    }

    LunchpailU64 maxThreadgroupMemory = 65536;
    const char *rawThreadgroupMemory = getenv("LUNCHPAIL_METAL_MAX_THREADGROUP_MEMORY");
    if (rawThreadgroupMemory && *rawThreadgroupMemory &&
        (!parseUnsignedEnvironmentValue(
            "LUNCHPAIL_METAL_MAX_THREADGROUP_MEMORY",
            &maxThreadgroupMemory
        ) || maxThreadgroupMemory < 16384 || maxThreadgroupMemory > 1048576)) {
        return NO;
    }

    LunchpailU64 recommendedWorkingSetSize = 0;
    const char *rawWorkingSetSize = getenv("LUNCHPAIL_METAL_RECOMMENDED_WORKING_SET_SIZE");
    BOOL hasRecommendedWorkingSetSize = rawWorkingSetSize && *rawWorkingSetSize;
    if (hasRecommendedWorkingSetSize &&
        (!parseUnsignedEnvironmentValue(
            "LUNCHPAIL_METAL_RECOMMENDED_WORKING_SET_SIZE",
            &recommendedWorkingSetSize
        ) || recommendedWorkingSetSize == 0 || recommendedWorkingSetSize > (1ULL << 48))) {
        return NO;
    }

    gConfiguration.enabled = YES;
    gConfiguration.appleFamilyMax = (NSUInteger)appleFamilyMax;
    gConfiguration.maxThreadgroupMemory = (NSUInteger)maxThreadgroupMemory;
    gConfiguration.hasRecommendedWorkingSetSize = hasRecommendedWorkingSetSize;
    gConfiguration.recommendedWorkingSetSize = (NSUInteger)recommendedWorkingSetSize;
    return YES;
}

static NSUInteger hookMaxThreadgroupMemoryLength(id self, SEL selector) {
    NSUInteger original = gOriginalMaxThreadgroupMemoryLength
        ? ((NSUInteger(*)(id, SEL))(void *)gOriginalMaxThreadgroupMemoryLength)(self, selector)
        : 0;
    return original < gConfiguration.maxThreadgroupMemory
        ? gConfiguration.maxThreadgroupMemory
        : original;
}

static NSUInteger hookRecommendedMaxWorkingSetSize(id self, SEL selector) {
    NSUInteger original = gOriginalRecommendedMaxWorkingSetSize
        ? ((NSUInteger(*)(id, SEL))(void *)gOriginalRecommendedMaxWorkingSetSize)(self, selector)
        : 0;
    return original < gConfiguration.recommendedWorkingSetSize
        ? gConfiguration.recommendedWorkingSetSize
        : original;
}

static BOOL hookSupportsFamily(id self, SEL selector, NSUInteger family) {
    BOOL original = gOriginalSupportsFamily
        ? ((BOOL(*)(id, SEL, NSUInteger))(void *)gOriginalSupportsFamily)(self, selector, family)
        : NO;
    BOOL isConfiguredAppleFamily = family >= 1001
        && family <= gConfiguration.appleFamilyMax;
    return original || isConfiguredAppleFamily;
}

static BOOL replaceMethod(
    Class deviceClass,
    NSString *selectorName,
    IMP replacement,
    IMP *original
) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(deviceClass, selector);
    if (!method) return NO;

    *original = method_setImplementation(method, replacement);
    return *original != NULL;
}

static void installDeviceHooks(id device) {
    @synchronized([device class]) {
        if (gDeviceHooksInstalled) return;

        Class deviceClass = [device class];
        Method maxThreadgroupMemory = class_getInstanceMethod(
            deviceClass,
            NSSelectorFromString(@"maxThreadgroupMemoryLength")
        );
        Method supportsFamily = class_getInstanceMethod(
            deviceClass,
            NSSelectorFromString(@"supportsFamily:")
        );
        Method recommendedWorkingSetSize = gConfiguration.hasRecommendedWorkingSetSize
            ? class_getInstanceMethod(
                  deviceClass,
                  NSSelectorFromString(@"recommendedMaxWorkingSetSize")
              )
            : NULL;

        if (!maxThreadgroupMemory || !supportsFamily ||
            (gConfiguration.hasRecommendedWorkingSetSize && !recommendedWorkingSetSize)) {
            NSLog(@"[LunchpailMetal] Required device methods unavailable; using stock capabilities");
            return;
        }

        BOOL installed = replaceMethod(
            deviceClass,
            @"maxThreadgroupMemoryLength",
            (IMP)hookMaxThreadgroupMemoryLength,
            &gOriginalMaxThreadgroupMemoryLength
        );
        installed = installed && replaceMethod(
            deviceClass,
            @"supportsFamily:",
            (IMP)hookSupportsFamily,
            &gOriginalSupportsFamily
        );

        if (installed && gConfiguration.hasRecommendedWorkingSetSize) {
            installed = replaceMethod(
                deviceClass,
                @"recommendedMaxWorkingSetSize",
                (IMP)hookRecommendedMaxWorkingSetSize,
                &gOriginalRecommendedMaxWorkingSetSize
            );
        }

        if (!installed) {
            NSLog(@"[LunchpailMetal] Capability hook installation was incomplete");
            return;
        }

        gDeviceHooksInstalled = YES;
        NSLog(
            @"[LunchpailMetal] Enabled for %@ (appleFamilyMax=%llu maxThreadgroupMemory=%llu)",
            [NSProcessInfo processInfo].processName,
            (LunchpailU64)gConfiguration.appleFamilyMax,
            (LunchpailU64)gConfiguration.maxThreadgroupMemory
        );
    }
}

static void hookInitGPUFamilySupport(id self, SEL selector) {
    installDeviceHooks(self);
    ((void(*)(id, SEL))(void *)gOriginalInitGPUFamilySupport)(self, selector);
}

__attribute__((constructor))
static void initializeLunchpailMetalCapabilities(void) {
    @autoreleasepool {
        if (!loadConfiguration()) return;

        Class deviceClass = NSClassFromString(@"_MTLDevice");
        if (!deviceClass) return;

        Method method = class_getInstanceMethod(
            deviceClass,
            NSSelectorFromString(@"initGPUFamilySupport")
        );
        if (!method) return;

        gOriginalInitGPUFamilySupport = method_setImplementation(
            method,
            (IMP)hookInitGPUFamilySupport
        );
    }
}
