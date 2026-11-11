// swift-tools-version: 5.6
//
// SPDX-FileCopyrightText: 2024 Stephen F. Booth <contact@sbooth.dev>
// SPDX-License-Identifier: MIT
//
// A trimmed copy of https://github.com/sbooth/SFBAudioEngine 0.14.0. See VENDORED.md.
//

import PackageDescription

let package = Package(
    name: "SFBAudioEngine",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "SFBAudioEngine",
            targets: [
                "CSFBAudioEngine",
                "SFBAudioEngine",
            ]),
    ],
    dependencies: [
        // Small MIT-licensed utilities by the engine's author
        .package(url: "https://github.com/sbooth/AVFAudioExtensions", .upToNextMinor(from: "0.5.1")),
        .package(url: "https://github.com/sbooth/CXXAudioRingBuffer", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/sbooth/CXXDispatchSemaphore", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/sbooth/CXXMessageQueue", .upToNextMinor(from: "0.2.2")),
        .package(url: "https://github.com/sbooth/CXXQueue", .upToNextMinor(from: "0.1.1")),
        .package(url: "https://github.com/sbooth/CXXUnfairLock", .upToNextMinor(from: "0.3.1")),

        // Xiph codecs, all BSD-licensed
        .package(url: "https://github.com/sbooth/ogg-binary-xcframework", .upToNextMinor(from: "0.1.3")),
        .package(url: "https://github.com/sbooth/flac-binary-xcframework", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/sbooth/opus-binary-xcframework", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/sbooth/vorbis-binary-xcframework", .upToNextMinor(from: "0.1.2")),
    ],
    targets: [
        .target(
            name: "CSFBAudioEngine",
            dependencies: [
                .product(name: "AVFAudioExtensions", package: "AVFAudioExtensions"),
                .product(name: "CXXAudioRingBuffer", package: "CXXAudioRingBuffer"),
                .product(name: "CXXDispatchSemaphore", package: "CXXDispatchSemaphore"),
                .product(name: "CXXMessageQueue", package: "CXXMessageQueue"),
                .product(name: "CXXQueue", package: "CXXQueue"),
                .product(name: "CXXUnfairLock", package: "CXXUnfairLock"),
                .product(name: "ogg", package: "ogg-binary-xcframework"),
                .product(name: "FLAC", package: "flac-binary-xcframework"),
                .product(name: "opus", package: "opus-binary-xcframework"),
                .product(name: "vorbis", package: "vorbis-binary-xcframework"),
            ],
            cSettings: [
                .headerSearchPath("include/SFBAudioEngine"),
                .headerSearchPath("Input"),
                .headerSearchPath("Decoders"),
                .headerSearchPath("Player"),
                .headerSearchPath("Output"),
                .headerSearchPath("Utilities"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("Foundation"),
            ]),
        .target(
            name: "SFBAudioEngine",
            dependencies: [
                "CSFBAudioEngine",
            ]),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
