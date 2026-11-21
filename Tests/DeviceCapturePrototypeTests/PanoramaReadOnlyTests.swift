import XCTest
@testable import DeviceCapturePrototype

final class PanoramaReadOnlyTests: XCTestCase {
    func testClassifyUSBHubAndInterfaceWithoutTreatingInterfaceAsDevice() {
        XCTAssertEqual(PanoramaClassifier.kind(className: "IOUSBHostDevice", properties: ["bDeviceClass": 9]), .hub)
        XCTAssertEqual(PanoramaClassifier.kind(className: "IOUSBHostInterface", properties: [:]), .interface)
        XCTAssertEqual(PanoramaClassifier.kind(className: "IOUSBHostDevice", properties: [:]), .device)
    }
    func testUnverifiedPhysicalPortAndSpeedRemainUnknown() {
        let evidence = PanoramaClassifier.physicalPortEvidence(location: 0x01100000)
        XCTAssertEqual(evidence, "物理端口待确认")
        XCTAssertNil(PanoramaClassifier.speedLabel(properties: ["USBSpeed": 3]))
    }
    func testCableIdentityOnlyUsesReportedMetadata() {
        let result = PanoramaClassifier.cableSummary(properties: ["Metadata": ["Vendor ID": 8386, "Product Type Description": "Passive Cable"]])
        XCTAssertTrue(result.contains("8386"))
        XCTAssertTrue(result.contains("Passive Cable"))
        XCTAssertFalse(result.contains("型号"))
        XCTAssertEqual(PanoramaClassifier.cableSummary(properties: [:]), "线材身份：系统未提供")
    }
    func testPowerSelectionUsesReportedValuesAndDoesNotClaimMeasuredPower() {
        let text = PanoramaClassifier.powerSummary(properties: ["WinningPowerSourceOption": ["Voltage (mV)": 28000, "Max Current (mA)": 4990, "Max Power (mW)": 139720]])
        XCTAssertTrue(text.contains("28000 mV"))
        XCTAssertTrue(text.contains("4990 mA"))
        XCTAssertTrue(text.contains("139720 mW"))
        XCTAssertTrue(text.contains("非实时功耗"))
        XCTAssertEqual(PanoramaClassifier.powerSummary(properties: [:]), "供电选项：系统未提供")
    }
    func testObservedPassiveCableDecodesOnlySupportedPD3Fields() {
        let data = [Data([0x1a,0x29,0x60,0x1c]), Data([0x43,0x09,0x00,0x00]), Data([0x90,0x01,0x01,0x84]), Data([0x44,0x26,0x0a,0x11])]
        let result = PanoramaPD.decodeCable(properties:["Specification Revision":3,"Metadata":["Vendor ID":10522,"Product ID":33793,"Product Type":3,"VDOs":data]])
        XCTAssertEqual(result?.vendorID,0x291a)
        XCTAssertEqual(result?.productID,0x8401)
        XCTAssertEqual(result?.maxCurrentAmps,5)
        XCTAssertEqual(result?.maxVoltageVolts,50)
        XCTAssertNil(result?.speedDescription)
        XCTAssertEqual(result?.rawVDOs.last,0x110a2644)
    }
    func testConflictingOrUnknownRevisionDoesNotProduceCableCapabilities() {
        let data = [Data([0x1a,0x29,0x60,0x1c]), Data([0,0,0,0]), Data([0x90,0x01,0x01,0x84]), Data([0x44,0x26,0x0a,0x11])]
        XCTAssertNil(PanoramaPD.decodeCable(properties:["Metadata":["Vendor ID":10522,"Product Type":3,"VDOs":data]]))
        XCTAssertNil(PanoramaPD.decodeCable(properties:["Specification Revision":3,"Metadata":["Vendor ID":1,"Product Type":3,"VDOs":data]]))
        XCTAssertNil(PanoramaPD.decodeCable(properties:["Specification Revision":3,"Metadata":["Vendor ID":10522,"Product Type":3,"VDOs":[Data([0x00])]]]))
    }

    func testPanoramaPriorityKeepsMacFirstAndUnownedAttachmentsOutOfPortRows() {
        let nodes = [
            PanoramaNode(
                id: 1,
                parentID: nil,
                name: "Mac",
                className: "IOUSBHostDevice",
                plane: "IOUSB",
                properties: [
                    "USB Product Name": "Mac",
                    "CPID": NSNumber(value: 24640),
                    "BDID": NSNumber(value: 4),
                ]),
            PanoramaNode(
                id: 2,
                parentID: nil,
                name: "Mac",
                className: "IOUSBHostDevice",
                plane: "IOUSB",
                properties: ["USB Product Name": "Mac"],
            ),
            PanoramaNode(
                id: 3,
                parentID: nil,
                name: "USB3.0 Hub",
                className: "IOUSBHostDevice",
                plane: "IOUSB",
                properties: [
                    "USB Product Name": "USB3.0 Hub",
                    "bDeviceClass": NSNumber(value: 9),
                ]),
            PanoramaNode(
                id: 4,
                parentID: nil,
                name: "SOP'",
                className: "IOPortTransportComponentCCUSBPDSOPp",
                plane: "IOService",
                properties: [
                    "Metadata": [
                        "Vendor ID": NSNumber(value: 0x291A),
                        "Product Type Description": "Passive Cable",
                    ],
                ]),
            PanoramaNode(
                id: 5,
                parentID: nil,
                name: "PowerSource",
                className: "IOPortFeaturePowerSource",
                plane: "IOService",
                properties: [:],
            ),
        ]

        let projection = PanoramaEntryBuilder.project(nodes: nodes)

        XCTAssertEqual(projection.primaryEntries.map(\.priority), [
            .identifiedMac,
            .unknownMac,
            .usbHubOrPeripheral,
        ])
        XCTAssertEqual(projection.unownedAttachments.map(\.nodeID), [4, 5])
        XCTAssertFalse(projection.primaryEntries.contains {
            $0.title.localizedCaseInsensitiveContains("RIGHT1")
        })
        XCTAssertTrue(projection.unownedAttachments.allSatisfy {
            $0.subtitle.contains("物理归属未证实")
        })
    }

    func testPanoramaMacIdentityUsesOnlyCurrentRegisteredFields() {
        let node = PanoramaNode(
            id: 10,
            parentID: nil,
            name: "Apple Mobile Device (DFU Mode)",
            className: "IOUSBHostDevice",
            plane: "IOUSB",
            properties: [
                "USB Product Name": "Apple Mobile Device (DFU Mode)",
                "CPID": NSNumber(value: 0x6031),
                "BDID": NSNumber(value: 0x44),
            ])
        let result = PanoramaEntryBuilder.identityResolution(for: node)
        XCTAssertEqual(result?.state, .uniqueCurrentMatch)
        XCTAssertEqual(result?.primaryModelIdentifier, "Mac15,8")
        XCTAssertEqual(result?.commonANumbers.count, 1)
    }

    func testAppleMobileDFUWithoutMacEvidenceIsNotShownAsUnknownMac() {
        let node = PanoramaNode(
            id: 11,
            parentID: nil,
            name: "Apple Mobile Device (DFU Mode)",
            className: "IOUSBHostDevice",
            plane: "IOUSB",
            properties: [
                "USB Product Name": "Apple Mobile Device (DFU Mode)",
            ])

        let projection = PanoramaEntryBuilder.project(nodes: [node])

        XCTAssertNil(PanoramaEntryBuilder.identityResolution(for: node))
        XCTAssertEqual(
            projection.primaryEntries.map(\.priority),
            [.usbHubOrPeripheral])
    }

    func testAX88179ANetworkAdapterHasNoSyntheticMacIdentity() {
        let node = PanoramaNode(
            id: 12,
            parentID: nil,
            name: "AX88179A",
            className: "IOUSBHostDevice",
            plane: "IOUSB",
            properties: [
                "USB Product Name": "AX88179A",
                "idVendor": NSNumber(value: 0x0B95),
                "idProduct": NSNumber(value: 0x1790),
            ])

        let projection = PanoramaEntryBuilder.project(nodes: [node])

        XCTAssertNil(PanoramaEntryBuilder.identityResolution(for: node))
        XCTAssertEqual(
            projection.primaryEntries.map(\.priority),
            [.usbHubOrPeripheral])
        XCTAssertFalse(
            projection.primaryEntries[0].title.contains("Mac"))
    }

    func testU5PowerContractUsesOnlyUniqueUSBCOwnership() {
        let port2 = PanoramaNode(
            id: 20,
            parentID: nil,
            name: "Port-USB-C@2",
            className: "AppleTCControllerType10",
            plane: "IOService",
            properties: [
                "PortNumber": NSNumber(value: 2),
                "PortTypeDescription": "USB-C",
            ])
        let contract = PanoramaNode(
            id: 21,
            parentID: port2.id,
            name: "USB-PD",
            className: "IOPortFeaturePowerSource",
            plane: "IOService",
            properties: [
                "ParentPortNumber": NSNumber(value: 2),
                "ParentBuiltInPortNumber": NSNumber(value: 2),
                "ParentBuiltInPortTypeDescription": "USB-C",
                "PowerSourceName": "USB-PD",
                "WinningPowerSourceOption": [
                    "Voltage (mV)": NSNumber(value: 28000),
                    "Max Current (mA)": NSNumber(value: 4990),
                    "Max Power (mW)": NSNumber(value: 139720),
                ],
            ])

        let result = PanoramaPowerAttribution.contract(
            forUSBCPortNumber: 2,
            nodes: [port2, contract])

        let attached = try? XCTUnwrap(result.contract)
        XCTAssertEqual(attached?.portNumber, 2)
        XCTAssertEqual(attached?.portType, "USB-C")
        XCTAssertEqual(attached?.sourceName, "USB-PD")
        XCTAssertEqual(attached?.voltageMillivolts, 28000)
        XCTAssertEqual(attached?.maxCurrentMilliamps, 4990)
        XCTAssertEqual(attached?.maxPowerMilliwatts, 139720)
        XCTAssertNotNil(attached?.capturedAt)
        XCTAssertEqual(attached?.isContractLimitOnly, true)
    }

    func testU5MagSafeAndConflictingUSBCContractsAreNotAttached() {
        let magsafe = PanoramaNode(
            id: 30,
            parentID: nil,
            name: "MagSafe 3",
            className: "IOPortFeaturePowerSource",
            plane: "IOService",
            properties: [
                "ParentPortNumber": NSNumber(value: 1),
                "ParentBuiltInPortTypeDescription": "MagSafe 3",
                "PowerSourceName": "USB-PD",
                "WinningPowerSourceOption": ["Max Power (mW)": NSNumber(value: 100000)],
            ])
        XCTAssertEqual(
            PanoramaPowerAttribution.contract(
                forUSBCPortNumber: 1,
                nodes: [magsafe]),
            .notUSBCOwned)

        let first = PanoramaNode(
            id: 31,
            parentID: nil,
            name: "USB-PD 1",
            className: "IOPortFeaturePowerSource",
            plane: "IOService",
            properties: [
                "ParentBuiltInPortNumber": NSNumber(value: 2),
                "ParentBuiltInPortTypeDescription": "USB-C",
                "WinningPowerSourceOption": ["Max Power (mW)": NSNumber(value: 100000)],
            ])
        let second = PanoramaNode(
            id: 32,
            parentID: nil,
            name: "USB-PD 2",
            className: "IOPortFeaturePowerSource",
            plane: "IOService",
            properties: [
                "ParentBuiltInPortNumber": NSNumber(value: 2),
                "ParentBuiltInPortTypeDescription": "USB-C",
                "WinningPowerSourceOption": ["Max Power (mW)": NSNumber(value: 60000)],
            ])
        XCTAssertEqual(
            PanoramaPowerAttribution.contract(
                forUSBCPortNumber: 2,
                nodes: [first, second]),
            .conflicting)
    }

    func testU6USBRootStatisticsAreReadPerNodeWithoutMerging() {
        let usb2 = PanoramaNode(
            id: 40,
            parentID: nil,
            name: "USB2 Root",
            className: "IOUSBHostDevice",
            plane: "IOUSB",
            properties: [
                "link-error-count": NSNumber(value: 3),
                "port-statistics": [
                    "kPortStatConnectCount": NSNumber(value: 7),
                    "kPortStatOverCurrentCount": NSNumber(value: 0),
                    "kPortStatEnumerationFailureCount": NSNumber(value: 2),
                    "kPortStatUSB3LinkFailureCount": NSNumber(value: 0xFFFF),
                ],
            ])
        let usb3 = PanoramaNode(
            id: 41,
            parentID: nil,
            name: "USB3 Root",
            className: "IOUSBHostDevice",
            plane: "IOUSB",
            properties: [
                "link-error-count": NSNumber(value: 9),
                "port-statistics": [
                    "kPortStatConnectCount": NSNumber(value: 11),
                ],
            ])

        let first = PanoramaUSBRootStatistics.read(from: usb2)
        let second = PanoramaUSBRootStatistics.read(from: usb3)

        XCTAssertEqual(first?.linkErrorCount, 3)
        XCTAssertEqual(first?.connectCount, 7)
        XCTAssertEqual(first?.overcurrentCount, 0)
        XCTAssertEqual(first?.enumerationFailureCount, 2)
        XCTAssertEqual(first?.usb3LinkFailureCount, 0xFFFF)
        XCTAssertEqual(second?.linkErrorCount, 9)
        XCTAssertEqual(second?.connectCount, 11)
        XCTAssertEqual(first?.isSaturated(first?.usb3LinkFailureCount), true)
    }
}
