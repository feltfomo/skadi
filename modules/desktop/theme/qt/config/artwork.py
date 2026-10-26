from xml.etree import ElementTree as ET


STATES = ("normal", "focused", "pressed", "toggled", "disabled")


class Artwork:
    def __init__(self):
        self.root = ET.Element("svg", xmlns="http://www.w3.org/2000/svg",
                               width="32", height="32", viewBox="0 0 32 32")

    def group(self, name):
        return ET.SubElement(self.root, "g", id=name)

    @staticmethod
    def rect(parent, width, height, fill, **attributes):
        return ET.SubElement(parent, "rect", width=str(width), height=str(height),
                             fill=fill, **{key.replace("_", "-"): str(value)
                                          for key, value in attributes.items()})

    @staticmethod
    def path(parent, data, color, width=1.5):
        return ET.SubElement(parent, "path", d=data, fill="none", stroke=color,
                             **{"stroke-width": str(width), "stroke-linecap": "round",
                                "stroke-linejoin": "round"})

    def panel(self, name, fill, border, radius=3, stroke=1):
        self.rect(self.group(name), 16, 16, fill)
        for edge, width, height, transform in [
            ("top", 16, radius, ""),
            ("bottom", 16, radius, f"translate(0 {radius}) scale(1 -1)"),
            ("left", 16, radius, "translate(0 16) rotate(-90)"),
            ("right", 16, radius, f"translate({radius} 0) rotate(90)"),
        ]:
            group = self.group(f"{name}-{edge}")
            inner = ET.SubElement(group, "g", transform=transform)
            self.rect(inner, width, height, fill)
            self.rect(inner, width, stroke, border)
        for corner, transform in [
            ("topleft", ""),
            ("topright", f"translate({radius} 0) scale(-1 1)"),
            ("bottomleft", f"translate(0 {radius}) scale(1 -1)"),
            ("bottomright", f"translate({radius} {radius}) scale(-1 -1)"),
        ]:
            group = self.group(f"{name}-{corner}")
            inner = ET.SubElement(group, "g", transform=transform)
            ET.SubElement(inner, "path", fill=fill,
                          d=f"M {radius} 0 A {radius} {radius} 0 0 0 0 {radius} "
                            f"H {radius} Z")
            inset = stroke / 2
            arc = radius - inset
            ET.SubElement(inner, "path", fill="none", stroke=border,
                          d=f"M {inset} {radius} A {arc} {arc} 0 0 1 {radius} {inset}",
                          **{"stroke-width": str(stroke), "stroke-linecap": "butt"})

    def focus(self, name, outer, inner, radius=3):
        self.panel(name, "none", outer, radius, 2)
        for edge in ("top", "bottom", "left", "right"):
            group = self.root.find(f"./g[@id='{name}-{edge}']/g")
            self.rect(group, 16, 1, inner, y=1)
        for corner in ("topleft", "topright", "bottomleft", "bottomright"):
            group = self.root.find(f"./g[@id='{name}-{corner}']/g")
            arc = radius - 1.5
            ET.SubElement(group, "path", fill="none", stroke=inner,
                          d=f"M 1.5 {radius} A {arc} {arc} 0 0 1 {radius} 1.5",
                          **{"stroke-width": "1", "stroke-linecap": "butt"})

    def indicator(self, name, data, color, background="none"):
        group = self.group(name)
        self.rect(group, 16, 16, background, rx=3)
        self.path(group, data, color)

    def check(self, name, fill, border, mark, radio=False, tristate=False):
        group = self.group(name)
        self.rect(group, 16, 16, "none")
        if radio:
            ET.SubElement(group, "circle", cx="8", cy="8", r="6.5", fill=fill,
                          stroke=border, **{"stroke-width": "1"})
            if mark:
                ET.SubElement(group, "circle", cx="8", cy="8", r="3", fill=mark)
        else:
            self.rect(group, 13, 13, fill, x=1.5, y=1.5, rx=3,
                      stroke=border, stroke_width=1)
            if mark:
                self.path(group, "M 4.5 8 H 11.5" if tristate else "M 4.5 8 L 7 10.5 L 11.5 5.5",
                          mark, 1.8)


def svg(roles):
    art = Artwork()
    r = roles
    ordinary = dict(normal=r["panel"], focused=r["hover"], pressed=r["pressed"],
                    toggled=r["primary"], disabled=r["panel"])
    selected = dict(normal="none", focused=r["hover"], pressed=r["primary"],
                    toggled=r["primary"], disabled="none")
    panels = {
        "button": (ordinary, 3),
        "toolbutton": (dict(ordinary, normal="none"), 3),
        "tab": (dict(selected, normal=r["panel"]), 3),
        "item": (selected, 3),
        "menuitem": (dict(selected, focused=r["primary"]), 3),
        "field": ({state: r["field"] for state in STATES}, 3),
        "panel": ({state: r["panel"] for state in STATES}, 3),
        "header": (dict(ordinary, toggled=r["hover"]), 3),
        "card": ({state: r["panel"] for state in STATES}, 5),
        "popup": ({state: r["panel"] for state in STATES}, 6),
        "tooltip": ({state: r["panel"] for state in STATES}, 3),
        "shell": ({state: r["shell"] for state in STATES}, 3),
        "groove": (dict(ordinary, normal=r["field"], toggled=r["primary"]), 3),
        "handle": (dict(ordinary, normal=r["primary"], focused=r["primary"],
                        pressed=r["selected_pressed"]), 3),
        "progress": ({state: r["primary"] for state in STATES}, 3),
        "scrollbar": (dict(ordinary, normal=r["border"], focused=r["strong_border"],
                           pressed=r["primary"], toggled=r["primary"]), 3),
    }
    for element, (fills, radius) in panels.items():
        for state, fill in fills.items():
            quiet = element in {"toolbutton", "item", "menuitem", "shell"}
            border = "none" if quiet else r["border"]
            if state == "focused" and not quiet:
                border = r["strong_border"]
            if state in {"pressed", "toggled"} and fill == r["primary"]:
                border = r["primary"]
            if element == "tooltip":
                border = r["strong_border"]
            for inactive in ("", "-inactive"):
                art.panel(f"{element}-{state}{inactive}", fill, border, radius)
        # the inner ink ring remains visible when the focused control is selected.
        art.focus(f"{element}-focus", r["primary"], r["on_primary"], radius)
    art.panel("button-default", "none", r["strong_border"], 3)
    art.focus("focus", r["primary"], r["on_primary"], 2)

    arrows = {
        "up": "M 4 10 L 8 6 L 12 10",
        "down": "M 4 6 L 8 10 L 12 6",
        "left": "M 10 4 L 6 8 L 10 12",
        "right": "M 6 4 L 10 8 L 6 12",
    }
    symbols = {
        "close": "M 5 5 L 11 11 M 11 5 L 5 11",
        "maximize": "M 4.5 4.5 H 11.5 V 11.5 H 4.5 Z",
        "minimize": "M 4.5 11 H 11.5",
        "restore": "M 4 6 H 10 V 12 H 4 Z M 6 4 H 12 V 10",
        "shade": "M 4 10 L 8 6 L 12 10",
    }
    for state in STATES:
        text = r["disabled_text"] if state == "disabled" else r["on_surface"]
        for inactive in ("", "-inactive"):
            ink = r["on_surface_variant"] if inactive else text
            for direction, data in arrows.items():
                art.indicator(f"arrow-{direction}-{state}{inactive}", data,
                              r["on_primary"] if state == "toggled" else ink)
                art.indicator(f"menuitem-{direction}-{state}{inactive}", data,
                              r["on_primary"] if state in {"focused", "pressed", "toggled"} else ink)
            for direction, data in {"plus": arrows["right"], "minus": arrows["down"]}.items():
                name = f"tree-{direction}-{state}{inactive}"
                art.indicator(name, data, r["on_primary"] if state == "pressed" else ink)
                if state == "focused":
                    # kvantum uses the same hover state on selected and ordinary branches.
                    art.path(art.root.find(f"./g[@id='{name}']"), data, r["on_primary"], 0.8)
            for symbol, data in symbols.items():
                art.indicator(f"mdi-{symbol}-{state}{inactive}", data, ink,
                              r["hover"] if state == "focused" else "none")
            art.indicator(f"tab-close-{state}{inactive}", symbols["close"],
                          r["on_primary"] if state == "toggled" else ink,
                          r["hover"] if state == "focused" else "none")
            art.indicator(f"sizegrip-{state}{inactive}", "M 5 12 L 12 5 M 9 12 L 12 9", ink)
            art.indicator(f"splitter-{state}{inactive}", "M 8 4 V 5 M 8 8 V 9 M 8 12 V 13",
                          r["border"])
            art.indicator(f"slider-tick-{state}{inactive}", "M 8 4 V 12", r["border"])
            for prefix in ("", "menu-", "item-"):
                for kind in ("checkbox", "radio"):
                    for check_state in ("", "checked-", "tristate-"):
                        # menu and item focused indicators sit on the selected background.
                        context = prefix and state == "focused"
                        checked = bool(check_state)
                        fill = r["primary"] if checked else r["field"]
                        border = r["primary"] if checked or state == "focused" else r["border"]
                        mark = r["on_primary"] if checked else None
                        if context:
                            fill = r["selected_hover"]
                            border = r["on_primary"]
                            mark = r["on_primary"] if checked else None
                        art.check(f"{prefix}{kind}-{check_state}{state}{inactive}",
                                  fill, border, mark, radio=kind == "radio",
                                  tristate=check_state == "tristate-")
    for state, fill in [("toggledFocused", r["selected_hover"]),
                        ("toggledPressed", r["selected_pressed"])]:
        for inactive in ("", "-inactive"):
            art.indicator(f"tab-close-{state}{inactive}", symbols["close"], r["on_primary"], fill)
    art.indicator("toolbar-handle", "M 6 4 V 12 M 10 4 V 12", r["border"])
    art.indicator("toolbar-separator", "M 8 2 V 14", r["border"], "none")
    art.indicator("menuitem-separator", "M 1 8 H 15", r["border"], "none")
    art.indicator("tab-tear", "M 8 1 V 15", r["border"], "none")
    for state in ("normal", "focused"):
        art.indicator(f"menuitem-tearoff-{state}", "M 1 8 H 5 M 7 8 H 11 M 13 8 H 15",
                      r["on_primary"] if state == "focused" else r["on_surface_variant"])
    return ET.tostring(art.root, encoding="unicode") + "\n"
