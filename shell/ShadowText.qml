import QtQuick

// Белый текст поверх обоев: тёмная обводка, чтобы он читался и на светлой картинке.
// Обводка, а не эффект тени: она рисуется при любом способе отрисовки и не требует памяти.
WText {
    color: "white"
    elide: Text.ElideNone
    style: Text.Outline
    styleColor: "#8c000000"
}
