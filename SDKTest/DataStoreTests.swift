//
//  DataStoreTests.swift
//  NeuroID
//
//  Created by Clayton Selby on 10/19/21.
//

import XCTest
@testable import NeuroID

class DataStoreTests: XCTestCase {
    let eventsKey = "events_pending"
    override func setUpWithError() throws {
        UserDefaults.standard.setValue(nil, forKey: "events_ending")
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testEncodeAndDecode() throws {
        var nid1 = NIDEvent(type: .radioChange, tg: ["name":TargetValue.string("clay")], view: UIView())

        let encoder = JSONEncoder()

        do {
            let jsonData = try encoder.encode([nid1])
            UserDefaults.standard.setValue(jsonData, forKey: eventsKey)
            let existingEvents = UserDefaults.standard.object(forKey: eventsKey)
            var parsedEvents = try JSONDecoder().decode([NIDEvent].self, from: existingEvents as! Data)
            var nid2 = NIDEvent(type: .radioChange, tg: ["name":TargetValue.string("clay")], view: UIView())
            parsedEvents.append(nid2)
            print(parsedEvents)
        } catch {
            print(String(describing: error))
        }
    }

    func testInsertDataStore() throws {
        // Reset the data store
        UserDefaults.standard.setValue(nil, forKey: eventsKey)
        let lv = LoanViewControllerPersonalDetails();
        let nid1 = NIDEvent(type: .radioChange, tg: ["name":TargetValue.string("clayton")], primaryViewController: LoanViewControllerPersonalDetails(), view: LoanViewControllerPersonalDetails().view)
        DataStore.insertEvent(screen: "screen1", event: nid1)
        let nid2 = NIDEvent(type: .radioChange, tg: ["name":TargetValue.string("bob")], primaryViewController: UIViewController(), view: UIView())
        DataStore.insertEvent(screen: "screen2", event: nid2)
        let newEvents = UserDefaults.standard.object(forKey: eventsKey)
        let parsedEvents = try JSONDecoder().decode([NIDEvent].self, from: newEvents as! Data)
        // Test Grouping
        let groupedEvents = Dictionary(grouping: parsedEvents, by: { (element: NIDEvent) in
            return element.url
        })
        print("Events:", parsedEvents)
        print("Grouped Events", groupedEvents)
        XCTAssert(parsedEvents.count == 2)
    }

    
}
