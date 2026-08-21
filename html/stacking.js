(function (root, factory) {
    const api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    root.COREXStackingUI = api;
})(typeof globalThis !== 'undefined' ? globalThis : window, function () {
    function getDefinition(definitions, itemName) {
        if (!itemName) return {};
        return definitions[itemName]
            || definitions[String(itemName).toLowerCase()]
            || definitions[String(itemName).toUpperCase()]
            || {};
    }

    function metadataEqual(left, right) {
        left = left || {};
        right = right || {};
        if (left === right) return true;
        if (typeof left !== typeof right || left === null || right === null) return false;
        if (typeof left !== 'object') return false;

        const leftKeys = Object.keys(left).sort();
        const rightKeys = Object.keys(right).sort();
        if (leftKeys.length !== rightKeys.length) return false;
        for (let index = 0; index < leftKeys.length; index += 1) {
            if (leftKeys[index] !== rightKeys[index]) return false;
            if (!metadataEqual(left[leftKeys[index]], right[rightKeys[index]])) return false;
        }
        return true;
    }

    function getItemAtCell(items, definitions, x, y, excludeSlot) {
        for (const item of items || []) {
            if (String(item.slot) === String(excludeSlot)) continue;
            const definition = getDefinition(definitions || {}, item.name);
            const width = definition.size?.w || 1;
            const height = definition.size?.h || 1;
            if (x >= item.x && x <= item.x + width - 1
                && y >= item.y && y <= item.y + height - 1) {
                return item;
            }
        }
        return null;
    }

    function canMerge(source, target, definitions) {
        if (!source || !target || String(source.slot) === String(target.slot)) return false;
        if (String(source.name).toUpperCase() !== String(target.name).toUpperCase()) return false;

        const definition = getDefinition(definitions || {}, source.name);
        if (definition.stackable !== true) return false;
        const maxStack = Math.max(1, Math.floor(Number(definition.maxStack) || 1));
        if ((Number(target.count) || 0) >= maxStack) return false;
        return metadataEqual(source.metadata, target.metadata);
    }

    return { getDefinition, metadataEqual, getItemAtCell, canMerge };
});
