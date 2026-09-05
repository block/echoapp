import XCTest
@testable import Echo

final class VersionTests: XCTestCase {
    
    // MARK: - Basic Comparison Tests
    
    func testBasicVersionComparison() {
        XCTAssertTrue(Version("1.0.0") < Version("2.0.0"))
        XCTAssertTrue(Version("1.0.0") < Version("1.1.0"))
        XCTAssertTrue(Version("1.0.0") < Version("1.0.1"))
        
        XCTAssertFalse(Version("2.0.0") < Version("1.0.0"))
        XCTAssertFalse(Version("1.1.0") < Version("1.0.0"))
        XCTAssertFalse(Version("1.0.1") < Version("1.0.0"))
    }
    
    func testEqualVersions() {
        XCTAssertFalse(Version("1.0.0") < Version("1.0.0"))
        XCTAssertFalse(Version("2.5.3") < Version("2.5.3"))
        XCTAssertEqual(Version("1.0.0"), Version("1.0.0"))
    }
    
    // MARK: - Version Prefix Tests
    
    func testVersionWithVPrefix() {
        XCTAssertTrue(Version("v1.0.0") < Version("v2.0.0"))
        XCTAssertTrue(Version("v1.0.0") < Version("2.0.0"))
        XCTAssertTrue(Version("1.0.0") < Version("v2.0.0"))
        // v-prefix versions are NOT equal to non-prefixed (rawValue differs)
        XCTAssertFalse(Version("v1.0.0") < Version("1.0.0"))
        XCTAssertFalse(Version("1.0.0") < Version("v1.0.0"))
    }
    
    // MARK: - Different Length Versions
    
    func testDifferentLengthVersions() {
        // Shorter vs longer versions
        XCTAssertTrue(Version("1.0") < Version("1.0.1"))
        XCTAssertTrue(Version("1") < Version("1.0.1"))
        XCTAssertTrue(Version("1") < Version("2"))
        
        // Missing components treated as 0
        XCTAssertFalse(Version("1.0.1") < Version("1.0"))
        XCTAssertFalse(Version("1.0.1") < Version("1"))
        
        // Equal when missing components are effectively 0
        XCTAssertFalse(Version("1.0") < Version("1.0.0"))
        XCTAssertFalse(Version("1.0.0") < Version("1.0"))
        XCTAssertFalse(Version("1") < Version("1.0.0"))
        XCTAssertFalse(Version("1.0.0") < Version("1"))
    }
    
    // MARK: - Multi-digit Version Components
    
    func testMultiDigitComponents() {
        XCTAssertTrue(Version("1.9.0") < Version("1.10.0"))
        XCTAssertTrue(Version("9.0.0") < Version("10.0.0"))
        XCTAssertTrue(Version("1.0.9") < Version("1.0.10"))
        
        // Ensure lexicographic ordering doesn't interfere
        XCTAssertTrue(Version("1.2.0") < Version("1.10.0"))
        XCTAssertFalse(Version("1.10.0") < Version("1.2.0"))
    }
    
    // MARK: - Complex Comparison Scenarios
    
    func testComplexComparisons() {
        let versions = [
            Version("0.9.0"),
            Version("1.0.0"),
            Version("1.0.1"),
            Version("1.1.0"),
            Version("2.0.0"),
            Version("v2.1.0"),
            Version("10.0.0")
        ]
        
        // Test that each version is less than all subsequent versions
        for i in 0..<versions.count {
            for j in (i+1)..<versions.count {
                XCTAssertTrue(
                    versions[i] < versions[j],
                    "\(versions[i].rawValue) should be < \(versions[j].rawValue)"
                )
            }
        }
        
        // Test non-numeric version components are ignored
        let alphaVersion = Version("1.0.0-alpha")
        let regularVersion = Version("1.0.0")
        // They are equal in comparison because only numeric parts matter
        XCTAssertFalse(alphaVersion < regularVersion)
        XCTAssertFalse(regularVersion < alphaVersion)
    }
    
    // MARK: - Edge Cases
    
    func testEdgeCases() {
        // Empty versions have no components
        let emptyVersion = Version("")
        let _ = Version("v") // Just test it doesn't crash
        let zeroVersion = Version("0")
        
        // They should behave consistently in comparisons
        XCTAssertFalse(emptyVersion < zeroVersion)
        XCTAssertTrue(zeroVersion < Version("1"))
        
        // Single component versions
        XCTAssertTrue(Version("1") < Version("2"))
        XCTAssertFalse(Version("2") < Version("1"))
        
        // Versions with many components
        XCTAssertTrue(Version("1.2.3.4.5") < Version("1.2.3.4.6"))
        XCTAssertTrue(Version("1.2.3.4") < Version("1.2.3.4.1"))
    }
    
    // MARK: - String Literal Support
    
    func testStringLiteralSupport() {
        let version: Version = "1.2.3"
        XCTAssertEqual(version.rawValue, "1.2.3")
        
        XCTAssertTrue("1.0.0" < "2.0.0" as Version)
        // v-prefix versions compare correctly but have different rawValue
        XCTAssertFalse("v1.0.0" < "1.0.0" as Version)
        XCTAssertFalse("1.0.0" < "v1.0.0" as Version)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        XCTAssertEqual(Version("1.2.3").description, "1.2.3")
        XCTAssertEqual(Version("v2.0.0").description, "v2.0.0")
        
        // Test rawValue property
        XCTAssertEqual(Version("1.0.0").rawValue, "1.0.0")
        XCTAssertEqual(Version("v2.0.0").rawValue, "v2.0.0")
    }
    
    // MARK: - Hashable Tests
    
    func testHashable() {
        let version1 = Version("1.2.3")
        let version2 = Version("1.2.3")
        let version3 = Version("v1.2.3")
        let version4 = Version("1.2.4")
        
        XCTAssertEqual(version1.hashValue, version2.hashValue)
        // v-prefix versions have different rawValue, so different hash
        XCTAssertNotEqual(version1.hashValue, version3.hashValue) 
        XCTAssertNotEqual(version1.hashValue, version4.hashValue)
        
        // Test with Set to ensure Hashable works correctly
        let versionSet: Set<Version> = [version1, version2, version3, version4]
        XCTAssertEqual(versionSet.count, 3) // version1 and version2 are equal, others differ
    }
    
    // MARK: - Performance Test
    
    func testComparisonPerformance() {
        let versions = (0..<1000).map { Version("\($0 % 10).\($0 % 5).\($0 % 3)") }
        
        measure {
            for i in 0..<versions.count {
                for j in 0..<versions.count {
                    _ = versions[i] < versions[j]
                }
            }
        }
    }
}