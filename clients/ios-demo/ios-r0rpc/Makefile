TARGET := iphone:clang:latest:13.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = r0rpc-ios-demo

r0rpc-ios-demo_FILES = \
	src/Tweak.x \
	src/Modules/yeemiao.x \
	src/Modules/teld.x \
	src/Core/RelayClient.m \
	src/Core/RPCConfig.m \
	src/Core/RPCResponse.m \
	src/Core/RelayBootstrap.m \
	src/Common/Store.m \
	src/Common/HookUtils.m \
	src/Common/PayloadUtils.m \
	src/Common/CaptureSession.m \
	src/Common/ObjCRuntimeUtils.m \
	src/Common/AlertManager.m \
	src/Common/NetworkHook.x \
	src/Common/UrlSourceHook.x \
	src/Common/SchemeHook.x \
	src/Common/CryptoGroup.x \
	src/utils/DeviceIdManager.m \
	src/utils/AppInfo.m \
	src/utils/NSString+JSON.m

r0rpc-ios-demo_CFLAGS = -fobjc-arc -Isrc -Isrc/Core -Isrc/Common -Isrc/utils -Wno-deprecated-declarations
r0rpc-ios-demo_FRAMEWORKS = Foundation UIKit Security

include $(THEOS_MAKE_PATH)/tweak.mk
