import Testing
@testable import PixelFerryCore

@Test func loDPIModeUsesOnePixelPerLogicalPoint() {
    let plan = DisplayModePlan.make(width: 1920, height: 1080, hiDPI: false)
    #expect(plan?.scale == 1)
    #expect(plan?.maximumPixelWidth == 1920)
    #expect(plan?.maximumPixelHeight == 1080)
    #expect(plan?.modes.first?.logicalWidth == 1920)
    #expect(plan?.modes.first?.pixelWidth == 1920)
}

@Test func hiDPIModeUsesTwoByTwoFramebufferPixels() {
    let plan = DisplayModePlan.make(width: 1920, height: 1080, hiDPI: true)
    #expect(plan?.scale == 2)
    #expect(plan?.maximumPixelWidth == 3840)
    #expect(plan?.maximumPixelHeight == 2160)
    #expect(plan?.modes.first?.logicalWidth == 1920)
    #expect(plan?.modes.first?.logicalHeight == 1080)
    #expect(plan?.modes.first?.pixelWidth == 3840)
    #expect(plan?.modes.first?.pixelHeight == 2160)
}

@Test func modePlanRejectsInvalidAndOverflowingDimensions() {
    #expect(DisplayModePlan.make(width: 0, height: 1080, hiDPI: false) == nil)
    #expect(DisplayModePlan.make(width: Int(UInt32.max), height: 1080, hiDPI: true) == nil)
}
