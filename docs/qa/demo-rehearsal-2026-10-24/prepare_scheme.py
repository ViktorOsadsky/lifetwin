"""Preserve Flutter's canonical prepare action in the temporary UI test scheme."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
root = Path(sys.argv[1]) / "Runner.xcodeproj/xcshareddata/xcschemes"
base = ET.parse(root / "Runner.xcscheme")
ui = ET.parse(root / "Demo133Acceptance.xcscheme")
test = base.getroot().find("TestAction")
test.remove(test.find("Testables"))
test.append(ui.getroot().find("TestAction/Testables"))
base.write(root / "Demo133Acceptance.xcscheme", encoding="utf-8", xml_declaration=True)
