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
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">'
        + '<path d="M16.5 3.9A9 9 0 1 0 20.8 14" stroke="' + ink + '" stroke-width="1.8" stroke-linecap="round"/>'
        + '<path d="M12 6.8v5.5l3.8 2.1" stroke="' + ink + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
        + '<circle cx="19.8" cy="6.4" r="1.5" fill="' + ink + '"/></svg>')
}
