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
        + '<path d="M5 20v-8c0-4 4-6 7-9 3 3 7 5 7 9v8H5Z" stroke="' + ink + '" stroke-width="1.8" stroke-linejoin="round"/>'
        + '<path d="M9 16a3 3 0 0 1 6 0M8 16h8" stroke="' + ink + '" stroke-width="1.8" stroke-linecap="round"/></svg>')
}
