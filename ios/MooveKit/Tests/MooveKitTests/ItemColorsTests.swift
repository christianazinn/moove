import Foundation
import Testing
@testable import MooveKit

@Suite struct ItemColorsTests {
    @Test func parsesModuleJSON() {
        let c = ItemColors(json: ##"{"primary":"#7B8B99","secondary":"#2b2a28"}"##)
        #expect(c == ItemColors(primary: 0x7B8B99, secondary: 0x2B2A28))
        #expect(ItemColors(json: ##"{"secondary":"#000000"}"##) == ItemColors(secondary: 0))
    }

    @Test func unknownOrMalformedIsNil() {
        for json in ["", "null", "[]", "{}", "not json", ##"{"primary":"7B8B99"}"##, ##"{"primary":"#7B8B9"}"##,
                     ##"{"primary":"#GGGGGG"}"##, ##"{"primary":123}"##] {
            #expect(ItemColors(json: json) == nil, "\(json)")
        }
        // One bad entry doesn't drop the good one.
        #expect(ItemColors(json: ##"{"primary":"#ZZZZZZ","secondary":"#102030"}"##) == ItemColors(secondary: 0x102030))
    }

    @Test func roundTripsToWireForm() {
        let c = ItemColors(primary: 0x0A0B0C, secondary: 0xFFEEDD)
        #expect(c.json == ##"{"primary":"#0A0B0C","secondary":"#FFEEDD"}"##)
        #expect(ItemColors(json: c.json) == c)
        #expect(ItemColors(primary: 0x7B8B99).json == ##"{"primary":"#7B8B99"}"##)
        #expect(ItemColors().json == "")
        #expect(ItemColors.hex(0x00FF00) == "#00FF00")
    }

    @Test func attributesJSON() {
        #expect(Item.attributes(json: #"["ChairType.swivel","ChairLegType.star"]"#) == ["ChairType.swivel", "ChairLegType.star"])
        #expect(Item.attributes(json: "[]").isEmpty)
        #expect(Item.attributes(json: "").isEmpty)
        #expect(Item.attributes(json: #"{"a":1}"#).isEmpty)
        #expect(Item.attributes(json: #"["A.b",3,null]"#) == ["A.b"])
    }
}
