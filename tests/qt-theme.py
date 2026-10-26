import configparser
import os
import sys
from pathlib import Path

from PyQt6 import QtCore, QtGui, QtSvg, QtWidgets


config_home, plugin_path, screenshot = map(Path, sys.argv[1:])
os.environ["XDG_CONFIG_HOME"] = str(config_home)
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ.pop("QT_QPA_PLATFORMTHEME", None)
os.environ.pop("QT_STYLE_OVERRIDE", None)
QtWidgets.QApplication.addLibraryPath(str(plugin_path))
app = QtWidgets.QApplication([])
style = QtWidgets.QStyleFactory.create("kvantum")
assert style is not None, QtWidgets.QStyleFactory.keys()
app.setStyle(style)

theme = config_home / "Kvantum/Skadi"
renderer = QtSvg.QSvgRenderer(str(theme / "Skadi.svg"))
assert renderer.isValid(), theme
config = configparser.ConfigParser(interpolation=None)
config.read(theme / "Skadi.kvconfig")
assert app.palette().color(QtGui.QPalette.ColorRole.Window).name() == config["GeneralColors"]["window.color"]
assert config["GeneralColors"]["progress.indicator.text.color"] == config["GeneralColors"]["highlight.text.color"]

window = QtWidgets.QWidget()
window.setWindowTitle("Skadi widget gallery")
window.setFont(QtGui.QFont("Maple Mono NF", 10))
layout = QtWidgets.QVBoxLayout(window)
tabs = QtWidgets.QTabWidget()
page = QtWidgets.QWidget()
controls = QtWidgets.QGridLayout(page)
entry = QtWidgets.QLineEdit("Editable field")
controls.addWidget(entry, 0, 0, 1, 2)
controls.addWidget(QtWidgets.QPushButton("Ordinary button"), 1, 0)
checked = QtWidgets.QPushButton("Selected button")
checked.setCheckable(True)
checked.setChecked(True)
controls.addWidget(checked, 1, 1)
disabled = QtWidgets.QPushButton("Disabled button")
disabled.setEnabled(False)
controls.addWidget(disabled, 2, 0)
combo = QtWidgets.QComboBox()
combo.addItems(["First choice", "Second choice"])
controls.addWidget(combo, 2, 1)
check = QtWidgets.QCheckBox("Checked")
check.setChecked(True)
controls.addWidget(check, 3, 0)
radio = QtWidgets.QRadioButton("Selected")
radio.setChecked(True)
controls.addWidget(radio, 3, 1)
slider = QtWidgets.QSlider(QtCore.Qt.Orientation.Horizontal)
slider.setValue(60)
controls.addWidget(slider, 4, 0, 1, 2)
progresses = QtWidgets.QWidget()
progress_layout = QtWidgets.QVBoxLayout(progresses)
progress_layout.setContentsMargins(0, 0, 0, 0)
for value in [10, 50, 60, 90]:
    progress = QtWidgets.QProgressBar()
    progress.setValue(value)
    progress_layout.addWidget(progress)
controls.addWidget(progresses, 5, 0, 1, 2)
items = QtWidgets.QTreeWidget()
items.setHeaderLabels(["Name", "Type"])
for name, kind in [("Selected folder", "Folder"), ("Document", "File")]:
    items.addTopLevelItem(QtWidgets.QTreeWidgetItem([name, kind]))
items.setCurrentItem(items.topLevelItem(0))
controls.addWidget(items, 6, 0, 1, 2)
tabs.addTab(page, "Selected tab")
tabs.addTab(QtWidgets.QWidget(), "Other tab")
layout.addWidget(tabs)
window.resize(560, 620)
window.show()
entry.setFocus()
app.processEvents()
image = window.grab()
assert not image.isNull()
assert image.save(str(screenshot)), screenshot
print("Kvantum loaded the custom SVG and rendered the Qt widget gallery")
