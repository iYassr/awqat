import QtQuick

// Vector rasterized only at the requested size; no animation, effects or font dependency.
Image {
    id: root
    property color ink: "#f38d70"
    width: 24
    height: 24
    sourceSize.width: Math.ceil(width * 2)
    sourceSize.height: Math.ceil(height * 2)
    smooth: true
    source: "data:image/svg+xml," + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" stroke="' + ink + '" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">'
        + '<path d="M11 52V32c0-12 10-18 17-24M53 52V32c0-12-10-18-17-24M21 51V34c0-7 5-12 11-17 6 5 11 10 11 17v17"/>'
        + '<circle cx="32" cy="42" r="3" fill="' + ink + '" stroke="none"/></svg>')
}
