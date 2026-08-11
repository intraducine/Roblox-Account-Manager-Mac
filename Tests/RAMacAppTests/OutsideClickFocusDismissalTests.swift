import AppKit
@testable import RAMacApp
import XCTest

final class OutsideClickFocusDismissalTests: XCTestCase {
    func testTextFieldsAndEditorsKeepFocusWhenClicked() {
        XCTAssertTrue(TextInputFocusPolicy.isTextInput(NSTextField()))
        XCTAssertTrue(TextInputFocusPolicy.isTextInput(NSSecureTextField()))
        XCTAssertTrue(TextInputFocusPolicy.isTextInput(NSTextView()))
    }

    func testChildOfTextInputKeepsFocus() {
        let textView = NSTextView()
        let child = NSView()
        textView.addSubview(child)

        XCTAssertTrue(TextInputFocusPolicy.isTextInput(child))
    }

    func testOtherControlsDismissTextFocus() {
        XCTAssertFalse(TextInputFocusPolicy.isTextInput(NSButton()))
        XCTAssertFalse(TextInputFocusPolicy.isTextInput(NSView()))
        XCTAssertFalse(TextInputFocusPolicy.isTextInput(NSTextField(labelWithString: "Help text")))
        XCTAssertFalse(TextInputFocusPolicy.isTextInput(nil))
    }

    func testOnlyEditableTextRespondersCountAsActiveTextInput() {
        let editable = NSTextView()
        editable.isEditable = true
        let readOnly = NSTextView()
        readOnly.isEditable = false

        XCTAssertTrue(TextInputFocusPolicy.isEditingText(editable))
        XCTAssertFalse(TextInputFocusPolicy.isEditingText(readOnly))
        XCTAssertTrue(TextInputFocusPolicy.isEditingText(NSTextField()))
        XCTAssertFalse(TextInputFocusPolicy.isEditingText(NSTextField(labelWithString: "Label")))
        XCTAssertFalse(TextInputFocusPolicy.isEditingText(NSButton()))
    }
}
