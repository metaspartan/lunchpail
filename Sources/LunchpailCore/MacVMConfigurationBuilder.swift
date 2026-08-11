import Foundation
import Virtualization

@MainActor
public enum MacVMConfigurationBuilder {
  public static func build(manifestURL: URL) throws -> VZVirtualMachineConfiguration {
    let manifest = try VMManifest.load(from: manifestURL)
    let baseURL = manifestURL.deletingLastPathComponent()
    return try build(manifest: manifest, baseURL: baseURL)
  }

  public static func build(
    manifest: VMManifest,
    baseURL: URL
  ) throws -> VZVirtualMachineConfiguration {
    try manifest.validate(baseURL: baseURL)

    guard let hardwareData = Data(base64Encoded: manifest.hardwareModelBase64),
      let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareData)
    else {
      throw VMManifestError.invalidHardwareModel
    }
    guard hardwareModel.isSupported else { throw VMManifestError.unsupportedHardwareModel }
    guard let identifierData = Data(base64Encoded: manifest.machineIdentifierBase64),
      let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: identifierData)
    else {
      throw VMManifestError.invalidMachineIdentifier
    }

    let configuration = VZVirtualMachineConfiguration()
    configuration.bootLoader = VZMacOSBootLoader()
    configuration.cpuCount = manifest.cpuCount
    configuration.memorySize = manifest.memoryBytes

    let platform = VZMacPlatformConfiguration()
    platform.hardwareModel = hardwareModel
    platform.machineIdentifier = machineIdentifier
    platform.auxiliaryStorage = VZMacAuxiliaryStorage(
      url: try manifest.bundleURL(for: manifest.auxiliaryStoragePath, baseURL: baseURL)
    )
    configuration.platform = platform

    let diskAttachment = try VZDiskImageStorageDeviceAttachment(
      url: manifest.bundleURL(for: manifest.diskPath, baseURL: baseURL),
      readOnly: false,
      cachingMode: .automatic,
      synchronizationMode: .fsync
    )
    configuration.storageDevices = [
      VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
    ]

    let graphics = VZMacGraphicsDeviceConfiguration()
    graphics.displays = [
      VZMacGraphicsDisplayConfiguration(
        widthInPixels: manifest.display.widthPixels,
        heightInPixels: manifest.display.heightPixels,
        pixelsPerInch: manifest.display.pixelsPerInch
      )
    ]
    configuration.graphicsDevices = [graphics]

    let network = VZVirtioNetworkDeviceConfiguration()
    network.attachment = VZNATNetworkDeviceAttachment()
    guard let macAddress = VZMACAddress(string: manifest.macAddress) else {
      throw VMManifestError.invalidMACAddress(manifest.macAddress)
    }
    network.macAddress = macAddress
    configuration.networkDevices = [network]

    configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    configuration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
    configuration.keyboards = [VZUSBKeyboardConfiguration(), VZMacKeyboardConfiguration()]
    configuration.pointingDevices = [
      VZUSBScreenCoordinatePointingDeviceConfiguration(),
      VZMacTrackpadConfiguration(),
    ]

    let sound = VZVirtioSoundDeviceConfiguration()
    sound.streams = [VZVirtioSoundDeviceOutputStreamConfiguration()]
    configuration.audioDevices = [sound]
    configuration.socketDevices = [VZVirtioSocketDeviceConfiguration()]

    if let sharedDirectoryPath = manifest.sharedDirectoryPath {
      let directory = VZSharedDirectory(
        url: try manifest.bundleURL(for: sharedDirectoryPath, baseURL: baseURL),
        readOnly: true
      )
      let share = VZSingleDirectoryShare(directory: directory)
      let device = VZVirtioFileSystemDeviceConfiguration(
        tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag
      )
      device.share = share
      configuration.directorySharingDevices = [device]
    }

    try configuration.validate()
    return configuration
  }
}
