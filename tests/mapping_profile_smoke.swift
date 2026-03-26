import Foundation
import Carbon.HIToolbox

@main
struct MappingProfileSmokeTests {
    static func main() {
        guard MappingProfile.defaultProfiles.count == 3 else {
            fputs("Expected 3 default profiles\n", stderr)
            exit(1)
        }

        guard MappingProfile.standardMac.mappings.isEmpty else {
            fputs("Expected Standard (Mac) profile to have no remaps\n", stderr)
            exit(1)
        }

        let windowsMappings = MappingProfile.windowsBluetooth.mappings
        guard windowsMappings[Int64(kVK_Control)] == Int64(kVK_Option) else {
            fputs("Expected Windows Bluetooth profile to map Control to Option\n", stderr)
            exit(1)
        }

        guard windowsMappings[Int64(kVK_Option)] == Int64(kVK_Command) else {
            fputs("Expected Windows Bluetooth profile to map Option to Command\n", stderr)
            exit(1)
        }

        print("mapping_profile_smoke: PASS")
    }
}
