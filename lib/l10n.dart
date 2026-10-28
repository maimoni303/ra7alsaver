/// Minimal two-language support (Arabic default, English).
/// `tx('عربي', 'English')` returns the text for the current language.
bool kEn = false;

String tx(String ar, String en) => kEn ? en : ar;
