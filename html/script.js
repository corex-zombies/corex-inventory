const CONFIG = {
    cellSize: 64,
    gapSize: 6,
    gridCols: 8,
    gridRows: 10,
    weightSegments: 20
};

/**
 * Dynamic icons (optional) in shared/items.lua:
 *   iconMetadataKey = 'model'   -- reads item.metadata.model
 * If iconFilenamePattern is omitted → uses "%s.png" (e.g. bmx.png, cruiser.png).
 * Or set iconFilenamePattern = 'prefix_%s.png' for a custom prefix.
 */
function getItemImageSrc(item, itemDef) {
    const def = itemDef || {};
    const defaultFromDef = def.image ? 'images/' + def.image : null;

    if (!item || !item.name) {
        return defaultFromDef || 'images/default.png';
    }

    const meta = item.metadata || {};
    const metaKey = def.iconMetadataKey;
    let pattern = def.iconFilenamePattern;

    if (typeof metaKey === 'string' && metaKey.length > 0) {
        if (typeof pattern !== 'string' || pattern.indexOf('%s') === -1) {
            pattern = '%s.png';
        }
        let raw = meta[metaKey] != null ? String(meta[metaKey]) : '';
        raw = raw.trim().toLowerCase();
        const safe = raw.replace(/[^a-z0-9_-]/g, '');
        if (safe) {
            const filename = pattern.replace('%s', safe);
            return 'images/' + filename;
        }
    }

    if (defaultFromDef) {
        return defaultFromDef;
    }

    const nm = String(item.name).toLowerCase();
    return 'images/' + nm + '.png';
}

let inventoryData = null;
let groundItems = [];
let itemsData = {};
let selectedItem = null;
let isDragging = false;
let draggedEl = null;
let draggedItem = null;
let draggedItemDef = null;
let dragSource = null;
let dragOffsetX = 0;
let dragOffsetY = 0;
let dragPreview = null;
let isActionPending = false;
let isBagMode = false;
let bagInventoryData = null;
let bagGridCols = 4;
let bagGridRows = 3;

function nuiRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
        return window.crypto.randomUUID();
    }
    return 'r_' + Date.now() + '_' + Math.random().toString(36).slice(2);
}

const container = document.getElementById('inventory-container');
const vehicleShopContainer = document.getElementById('vehicle-shop-container');
const playerGrid = document.getElementById('player-grid');
const dropGrid = document.getElementById('drop-grid');
const contextMenu = document.getElementById('context-menu');
const weightSegmentsContainer = document.getElementById('weight-segments');
const bagWeightSegmentsContainer = document.getElementById('bag-weight-segments');
const bagWeightText = document.getElementById('bag-weight-text');

function initializeUI() {
    renderSlots(playerGrid, CONFIG.gridCols, CONFIG.gridRows);
    renderSlots(dropGrid, CONFIG.gridCols, CONFIG.gridRows);
    renderWeightSegments();
    createDragPreview();
}

function renderSlots(grid, cols, rows) {
    grid.innerHTML = '';
    grid.style.gridTemplateColumns = `repeat(${cols}, ${CONFIG.cellSize}px)`;

    const frag = document.createDocumentFragment();
    for (let row = 1; row <= rows; row++) {
        for (let col = 1; col <= cols; col++) {
            const slot = document.createElement('div');
            slot.className = 'slot';
            slot.dataset.col = col;
            slot.dataset.row = row;
            frag.appendChild(slot);
        }
    }
    grid.appendChild(frag);
}

function renderWeightSegments() {
    weightSegmentsContainer.innerHTML = '';
    const frag = document.createDocumentFragment();
    for (let i = 0; i < CONFIG.weightSegments; i++) {
        const segment = document.createElement('div');
        segment.className = 'weight-segment';
        frag.appendChild(segment);
    }
    weightSegmentsContainer.appendChild(frag);
}

function createDragPreview() {
    if (dragPreview) dragPreview.remove();
    dragPreview = document.createElement('div');
    dragPreview.className = 'drag-preview hidden';
    document.body.appendChild(dragPreview);
}

function updateWeightBar(current, max) {
    const segments = weightSegmentsContainer.querySelectorAll('.weight-segment');
    const percentage = Math.min((current / max) * 100, 100);
    const filledCount = Math.round((percentage / 100) * CONFIG.weightSegments);

    segments.forEach((segment, index) => {
        segment.classList.remove('filled', 'warning', 'danger');
        if (index < filledCount) {
            if (percentage >= 90) {
                segment.classList.add('danger');
            } else if (percentage >= 70) {
                segment.classList.add('warning');
            } else {
                segment.classList.add('filled');
            }
        }
    });

    document.getElementById('current-weight').textContent = Math.round(current);
    document.getElementById('max-weight').textContent = Math.round(max);
}

function checkCollision(x, y, w, h, items, excludeSlot) {
    if (x < 1 || y < 1 || x + w - 1 > CONFIG.gridCols || y + h - 1 > CONFIG.gridRows) {
        return true;
    }

    for (const item of items) {
        if (item.slot === excludeSlot) continue;

        const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 } };
        const itemW = itemDef.size?.w || 1;
        const itemH = itemDef.size?.h || 1;

        const itemRight = item.x + itemW - 1;
        const itemBottom = item.y + itemH - 1;
        const newRight = x + w - 1;
        const newBottom = y + h - 1;

        const overlapsX = !(newRight < item.x || x > itemRight);
        const overlapsY = !(newBottom < item.y || y > itemBottom);

        if (overlapsX && overlapsY) {
            return true;
        }
    }

    return false;
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();

        if (isDragging) {
            cancelDrag();
        } else if (!container.classList.contains('hidden') || (vehicleShopContainer && !vehicleShopContainer.classList.contains('hidden'))) {
            closeInventory();
        }
    }
});

document.addEventListener('click', (e) => {
    if (!contextMenu.contains(e.target)) {
        hideContextMenu();
    }
});

function openInventory(data) {
    inventoryData = data;
    itemsData = data.itemsData || {};

    // Store items globally for hotbar (same as updateInventory)
    if (data && data.items) {
        window.latestInventoryItems = data.items;
    }

    if (data.grid) {
        CONFIG.gridCols = data.grid.w || 8;
        CONFIG.gridRows = data.grid.h || 10;
    }

    if (data.groundItems) {
        groundItems = data.groundItems;
    }

    const dropTitle = document.getElementById('drop-title');
    const dropIcon = document.getElementById('drop-icon');
    const dropHint = document.getElementById('drop-hint');
    const shopMoney = document.getElementById('shop-money');
    const playerMoneySpan = document.getElementById('player-money');

    if (data.isShop) {
        dropTitle.textContent = data.shopName || 'Shop';
        dropIcon.className = 'fa-solid fa-store hex-inner-icon';
        dropHint.classList.add('hidden');
        shopMoney.classList.remove('hidden');
        playerMoneySpan.textContent = '$' + (data.playerMoney || 0);
        dropGrid.classList.add('is-shop');
    } else {
        dropTitle.textContent = 'Ground';
        dropIcon.className = 'fa-solid fa-arrow-down hex-inner-icon';
        dropHint.classList.remove('hidden');
        shopMoney.classList.add('hidden');
        dropGrid.classList.remove('is-shop');
    }

    initializeUI();
    updateWeightBar(data.weight || 0, data.maxWeight || 200);
    renderItems();
    renderGroundItems();
    container.classList.remove('hidden');
}

function updateInventory(data) {
    inventoryData = data;
    if (data.itemsData) itemsData = data.itemsData;

    // Store items globally so hotbar can update even when inventory is closed
    if (data && data.items) {
        window.latestInventoryItems = data.items;
        assignHotkeysToSlots(data.items); // Always update hotbar
    }

    updateWeightBar(data.weight || 0, data.maxWeight || 200);
    renderItems();
}

function updateGroundItems(items) {
    groundItems = items;
    renderGroundItems();
}

function closeInventory() {
    if (container.classList.contains('hidden')) return;

    if (isContainerMode) {
        const cId = containerData?.containerId;
        closeLootContainer();
        fetch(`https://${GetParentResourceName()}/closeLootContainer`, {
            method: 'POST',
            body: JSON.stringify({ containerId: cId })
        }).catch(() => {});
    }

    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        body: JSON.stringify({})
    }).catch(() => {});
}

function cancelDrag() {
    if (draggedEl) {
        draggedEl.classList.remove('dragging');
        draggedEl.style.position = '';
        draggedEl.style.zIndex = '';
        draggedEl.style.left = '';
        draggedEl.style.top = '';
    }

    isDragging = false;
    draggedEl = null;
    draggedItem = null;
    draggedItemDef = null;
    dragSource = null;
    hideDragPreview();

    document.removeEventListener('mousemove', handleDragMove);
    document.removeEventListener('mouseup', handleDragEnd);

    renderItems();
    renderGroundItems();
}

function renderItems() {
    playerGrid.querySelectorAll('.item').forEach(item => item.remove());
    playerGrid.querySelectorAll('.quickslot-number').forEach(num => num.remove());

    if (!inventoryData || !inventoryData.items) {
        assignHotkeysToSlots([]);
        return;
    }

    const frag = document.createDocumentFragment();
    inventoryData.items.forEach(item => {
        frag.appendChild(createItemElement(item, 'player'));
    });
    playerGrid.appendChild(frag);

    assignHotkeysToSlots(inventoryData.items);
}

function assignHotkeysToSlots(items) {
    const coveredSlots = new Set();
    const anchorSlots = new Map();

    items.forEach(item => {
        const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 } };
        const w = itemDef.size?.w || 1;
        const h = itemDef.size?.h || 1;
        const anchorKey = `${item.x},${item.y}`;
        anchorSlots.set(anchorKey, item);

        for (let row = item.y; row < item.y + h; row++) {
            for (let col = item.x; col < item.x + w; col++) {
                const key = `${col},${row}`;
                if (key !== anchorKey) {
                    coveredSlots.add(key);
                }
            }
        }
    });

    let currentHotkey = 1;
    const hotkeyMapping = [];

    for (let row = 1; row <= CONFIG.gridRows && currentHotkey <= 6; row++) {
        for (let col = 1; col <= CONFIG.gridCols && currentHotkey <= 6; col++) {
            const key = `${col},${row}`;

            if (coveredSlots.has(key)) {
                continue;
            }

            const slot = playerGrid.querySelector(`.slot[data-col="${col}"][data-row="${row}"]`);
            if (!slot) continue;

            if (anchorSlots.has(key)) {
                const item = anchorSlots.get(key);
                const itemEl = playerGrid.querySelector(`.item[data-x="${col}"][data-y="${row}"]`);
                if (itemEl) {
                    const numBadge = document.createElement('span');
                    numBadge.className = 'quickslot-number';
                    numBadge.textContent = currentHotkey;
                    itemEl.appendChild(numBadge);
                }
                hotkeyMapping[currentHotkey] = { col, row, type: 'item', item };
                currentHotkey++;
            } else {
                const numBadge = document.createElement('span');
                numBadge.className = 'quickslot-number';
                numBadge.textContent = currentHotkey;
                slot.appendChild(numBadge);
                hotkeyMapping[currentHotkey] = { col, row, type: 'empty' };
                currentHotkey++;
            }
        }
    }

    window.hotkeyMapping = hotkeyMapping;
    syncHotbarWithInventory(hotkeyMapping);
}

function syncHotbarWithInventory(hotkeyMapping) {
    const hotbarSlots = document.querySelectorAll('.hotbar-slot');

    hotbarSlots.forEach(slot => {
        const slotNum = parseInt(slot.dataset.slot);
        const mapping = hotkeyMapping[slotNum];

        // Clear current slot
        const existingImg = slot.querySelector('.hotbar-item-image');
        const existingCount = slot.querySelector('.hotbar-item-count');
        const existingRarity = slot.querySelector('.hotbar-rarity-bar'); // if any from previous generic render

        if (existingImg) existingImg.remove();
        if (existingCount) existingCount.remove();
        if (existingRarity) existingRarity.remove();

        slot.className = 'hotbar-slot';
        delete slot.dataset.rarity;

        if (mapping && mapping.type === 'item' && mapping.item) {
            const item = mapping.item;

            let itemDef = itemsData[item.name];
            if (!itemDef) itemDef = itemsData[item.name.toLowerCase()];
            if (!itemDef) itemDef = itemsData[item.name.toUpperCase()];
            if (!itemDef) {
                itemDef = Object.values(itemsData).find(d => d.label === item.name || d.name === item.name);
            }
            if (!itemDef) itemDef = {};

            const rarity = itemDef.rarity || item.rarity || 'common';

            slot.classList.add('has-item');
            slot.dataset.rarity = rarity;

            const img = document.createElement('img');
            img.className = 'hotbar-item-image';
            img.src = getItemImageSrc(item, itemDef);
            img.alt = itemDef.label || item.name;
            img.onerror = function () {
                this.onerror = null;
                this.src = 'images/default.png';
            };

            const count = document.createElement('span');
            count.className = 'hotbar-item-count';
            if (item.count >= 1) count.textContent = item.count;

            slot.appendChild(img);
            slot.appendChild(count);
        }
    });
}

function renderGroundItems() {
    dropGrid.querySelectorAll('.item').forEach(item => item.remove());
    dropGrid.querySelectorAll('.shop-card').forEach(item => item.remove());

    if (inventoryData && inventoryData.isShop) {
        const frag = document.createDocumentFragment();
        groundItems.forEach((item) => {
            frag.appendChild(createShopCard(item));
        });
        dropGrid.appendChild(frag);
        return;
    }

    const frag = document.createDocumentFragment();
    groundItems.forEach((item) => {
        frag.appendChild(createItemElement(item, 'ground'));
    });
    dropGrid.appendChild(frag);
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

function purchaseShopItem(item, amount = 1) {
    if (!inventoryData || !inventoryData.isShop || !item || !item.name) return;
    if (isActionPending) return;

    isActionPending = true;
    fetch(`https://${GetParentResourceName()}/purchaseShopItem`, {
        method: 'POST',
        body: JSON.stringify({
            itemName: item.name,
            amount: amount
        })
    }).catch(() => {}).finally(() => {
        setTimeout(() => {
            isActionPending = false;
        }, 450);
    });
}

function createShopCard(item) {
    let itemDef = itemsData[item.name];
    if (!itemDef) itemDef = itemsData[item.name.toLowerCase()];
    if (!itemDef) itemDef = itemsData[item.name.toUpperCase()];
    if (!itemDef) {
        itemDef = Object.values(itemsData).find(d => d.label === item.name || d.name === item.name) || { label: item.name, description: 'No description available.', size: {w:1, h:1} };
    }

    const rarity = itemDef.rarity || 'common';
    const rarityLabel = rarity.charAt(0).toUpperCase() + rarity.slice(1);

    const el = document.createElement('div');
    el.className = `shop-card rarity-border-${rarity}`;

    const cat = itemDef.category || 'Item';
    const itemLabel = itemDef.label || item.name;
    const itemDesc = itemDef.description ? itemDef.description : 'A valuable survival item.';
    const imageName = itemDef.image || item.name.toLowerCase() + '.png';

    el.innerHTML = `
        <div class="shop-card-content">
            <div class="shop-card-image rarity-bg-${rarity}">
                <img src="images/${escapeHtml(imageName)}" onerror="this.onerror=null;this.src='images/default.png';" alt="">
            </div>
            <div class="shop-card-info">
                <div class="shop-card-header">
                    <span class="shop-card-name">${escapeHtml(itemLabel)}</span>
                    <span class="shop-card-price">$${item.price || 0}</span>
                </div>
                <div class="shop-card-desc">${escapeHtml(itemDesc)}</div>
                <div class="shop-card-footer">
                    <div class="shop-card-tags">
                        <span class="shop-card-cat">${escapeHtml(cat)}</span>
                        <span class="shop-card-rarity rarity-text-${rarity}">${escapeHtml(rarityLabel)}</span>
                    </div>
                    <button class="shop-buy-btn" type="button">BUY</button>
                </div>
            </div>
        </div>
    `;

    el.dataset.slot = item.slot;
    el.dataset.name = item.name;
    el.dataset.count = item.count || 1;
    el.dataset.source = 'ground';
    el.dataset.isShopItem = 'true';
    el.dataset.price = item.price || 0;
    el.dataset.currency = item.currency || 'cash';

    const buyButton = el.querySelector('.shop-buy-btn');
    if (buyButton) {
        buyButton.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            purchaseShopItem(item, 1);
        });
    }
    el.addEventListener('dblclick', () => purchaseShopItem(item, 1));
    return el;
}

function createItemElement(item, source, quickslotNum) {
    const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 }, label: item.name, weight: 0 };
    const displaySize = item.isShopItem && item.displaySize ? item.displaySize : (itemDef.size || { w: 1, h: 1 });
    const w = displaySize.w || 1;
    const h = displaySize.h || 1;
    const category = itemDef.category || '';
    const isAmmoItem = item.name.toLowerCase().includes('ammo') || (!!itemDef.maxStack && !itemDef.ammoType && !category);
    const itemTypeClass = isAmmoItem ? 'item-type-ammo' : 'item-type-weapon';
    const categoryClass = category ? `item-category-${category}` : '';
    const rarity = itemDef.rarity || 'common';
    const rarityLabel = {
        common: 'COMMON',
        uncommon: 'UNCOMMON',
        rare: 'RARE',
        epic: 'EPIC',
        legendary: 'LEGENDARY'
    }[rarity] || 'COMMON';

    const el = document.createElement('div');
    el.className = `item rarity-${rarity}`;
    if (item.isShopItem) {
        el.classList.add('shop-item');
        el.classList.add(itemTypeClass);
        if (categoryClass) {
            el.classList.add(categoryClass);
        }
        if (w === 1 && h === 1) {
            el.classList.add('shop-item-compact');
        } else if (w >= 2 && h >= 2) {
            el.classList.add('shop-item-large');
        }
    }

    const x = Math.max(1, Math.min(item.x || 1, CONFIG.gridCols));
    const y = Math.max(1, Math.min(item.y || 1, CONFIG.gridRows));

    const left = (x - 1) * (CONFIG.cellSize + CONFIG.gapSize);
    const top = (y - 1) * (CONFIG.cellSize + CONFIG.gapSize);
    const width = w * CONFIG.cellSize + (w - 1) * CONFIG.gapSize;
    const height = h * CONFIG.cellSize + (h - 1) * CONFIG.gapSize;

    el.style.left = left + 'px';
    el.style.top = top + 'px';
    el.style.width = width + 'px';
    el.style.height = height + 'px';

    const totalWeight = ((itemDef.weight || 0) * (item.count || 1)).toFixed(2);
    const quickslotBadge = quickslotNum ? `<span class="quickslot-number">${quickslotNum}</span>` : '';
    const priceTag = item.isShopItem ? `<span class="item-price">$${item.price || 0}</span>` : '';

    el.innerHTML = '';
    const fragment = document.createDocumentFragment();
    if (quickslotBadge) {
        const qs = document.createElement('span');
        qs.className = 'quickslot-number';
        qs.textContent = quickslotNum;
        fragment.appendChild(qs);
    }
    const rarityEl = document.createElement('span');
    rarityEl.className = 'item-rarity';
    rarityEl.textContent = rarityLabel;
    fragment.appendChild(rarityEl);
    const qtyEl = document.createElement('span');
    qtyEl.className = 'item-qty';
    qtyEl.textContent = item.count || 1;
    fragment.appendChild(qtyEl);
    const weightEl = document.createElement('span');
    weightEl.className = 'item-weight';
    weightEl.textContent = totalWeight + 'kg';
    fragment.appendChild(weightEl);
    if (item.isShopItem) {
        const priceEl = document.createElement('span');
        priceEl.className = 'item-price';
        priceEl.textContent = '$' + (item.price || 0);
        fragment.appendChild(priceEl);
    }
    const img = document.createElement('img');
    img.src = getItemImageSrc(item, itemDef);
    img.alt = itemDef.label || '';
    img.onerror = function() { this.onerror = null; this.src = 'images/default.png'; };
    fragment.appendChild(img);
    const nameEl = document.createElement('span');
    nameEl.className = 'item-name';
    nameEl.textContent = itemDef.label || item.name;
    fragment.appendChild(nameEl);
    el.appendChild(fragment);

    el.dataset.slot = item.slot;
    el.dataset.name = item.name;
    el.dataset.count = item.count || 1;
    el.dataset.source = source;
    el.dataset.x = x;
    el.dataset.y = y;
    if (item.isShopItem) {
        el.dataset.isShopItem = 'true';
        el.dataset.price = item.price || 0;
        el.dataset.currency = item.currency || 'cash';
    }

    el.addEventListener('contextmenu', (e) => showContextMenu(e, item, source, el));
    el.addEventListener('mousedown', (e) => handleDragStart(e, el, item, source));

    return el;
}

function hideDragPreview() {
    if (!dragPreview) return;
    dragPreview.classList.add('hidden');
    dragPreview.classList.remove('valid', 'invalid', 'drop-zone');
    dragPreview.style.left = '';
    dragPreview.style.top = '';
    dragPreview.style.width = '';
    dragPreview.style.height = '';
}

function getSlotAtPoint(grid, clientX, clientY) {
    if (!grid) return null;
    const node = document.elementFromPoint(clientX, clientY);
    const slot = node && node.closest ? node.closest('.slot') : null;
    if (!slot || !grid.contains(slot)) return null;
    return {
        x: parseInt(slot.dataset.col, 10),
        y: parseInt(slot.dataset.row, 10),
        slot
    };
}

function getItemSize(item) {
    const itemDef = itemsData[item.name] || itemsData[item.name?.toLowerCase?.()] || itemsData[item.name?.toUpperCase?.()] || {};
    const size = item.displaySize || itemDef.size || { w: 1, h: 1 };
    return {
        w: size.w || 1,
        h: size.h || 1
    };
}

function showDragPreviewAt(slot, item, valid, dropZone) {
    if (!dragPreview || !slot) return;
    const size = getItemSize(item);
    const rect = slot.slot.getBoundingClientRect();
    const width = size.w * CONFIG.cellSize + (size.w - 1) * CONFIG.gapSize;
    const height = size.h * CONFIG.cellSize + (size.h - 1) * CONFIG.gapSize;

    dragPreview.classList.remove('hidden', 'valid', 'invalid', 'drop-zone');
    dragPreview.classList.add(dropZone ? 'drop-zone' : (valid ? 'valid' : 'invalid'));
    dragPreview.style.left = rect.left + 'px';
    dragPreview.style.top = rect.top + 'px';
    dragPreview.style.width = width + 'px';
    dragPreview.style.height = height + 'px';
}

function handleDragStart(e, el, item, source) {
    if (e.button !== 0 || isActionPending) return;
    if (source === 'container') return;
    if (inventoryData && inventoryData.isShop && source === 'ground') return;

    e.preventDefault();
    e.stopPropagation();
    hideContextMenu();

    isDragging = true;
    draggedEl = el;
    draggedItem = item;
    draggedItemDef = itemsData[item.name] || {};
    dragSource = source;

    const rect = el.getBoundingClientRect();
    dragOffsetX = e.clientX - rect.left;
    dragOffsetY = e.clientY - rect.top;

    el.classList.add('dragging');
    el.style.position = 'fixed';
    el.style.left = rect.left + 'px';
    el.style.top = rect.top + 'px';
    el.style.zIndex = '1000';

    document.addEventListener('mousemove', handleDragMove);
    document.addEventListener('mouseup', handleDragEnd);
}

function handleDragMove(e) {
    if (!isDragging || !draggedEl || !draggedItem) return;

    draggedEl.style.left = (e.clientX - dragOffsetX) + 'px';
    draggedEl.style.top = (e.clientY - dragOffsetY) + 'px';

    const playerSlot = getSlotAtPoint(playerGrid, e.clientX, e.clientY);
    const dropSlot = getSlotAtPoint(dropGrid, e.clientX, e.clientY);
    const size = getItemSize(draggedItem);

    if (dragSource === 'player' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || [], draggedItem.slot);
        showDragPreviewAt(playerSlot, draggedItem, valid, false);
    } else if (dragSource === 'ground' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || []);
        showDragPreviewAt(playerSlot, draggedItem, valid, false);
    } else if (dragSource === 'bag' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || []);
        showDragPreviewAt(playerSlot, draggedItem, valid, false);
    } else if (dragSource === 'player' && dropSlot) {
        if (isBagMode) {
            const valid = !checkBagCollision(dropSlot.x, dropSlot.y, size.w, size.h, bagInventoryData?.items || []);
            showDragPreviewAt(dropSlot, draggedItem, valid, false);
        } else {
            showDragPreviewAt(dropSlot, draggedItem, true, true);
        }
    } else if (dragSource === 'bag' && dropSlot) {
        const valid = !checkBagCollision(dropSlot.x, dropSlot.y, size.w, size.h, bagInventoryData?.items || [], draggedItem.slot);
        showDragPreviewAt(dropSlot, draggedItem, valid, false);
    } else {
        hideDragPreview();
    }
}

function handleDragEnd(e) {
    if (!isDragging || !draggedItem) {
        cancelDrag();
        return;
    }

    const playerSlot = getSlotAtPoint(playerGrid, e.clientX, e.clientY);
    const dropSlot = getSlotAtPoint(dropGrid, e.clientX, e.clientY);
    const size = getItemSize(draggedItem);

    if (dragSource === 'player' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || [], draggedItem.slot);
        if (valid) {
            fetch(`https://${GetParentResourceName()}/moveItem`, {
                method: 'POST',
                body: JSON.stringify({
                    slotId: draggedItem.slot,
                    x: playerSlot.x,
                    y: playerSlot.y
                })
            }).catch(() => {});
        }
    } else if (dragSource === 'bag' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || []);
        if (valid) {
            fetch(`https://${GetParentResourceName()}/moveFromBag`, {
                method: 'POST',
                body: JSON.stringify({ bagSlot: draggedItem.slot, playerX: playerSlot.x, playerY: playerSlot.y })
            }).catch(() => {});
        }
    } else if (dragSource === 'bag' && dropSlot) {
        const valid = !checkBagCollision(dropSlot.x, dropSlot.y, size.w, size.h, bagInventoryData?.items || [], draggedItem.slot);
        if (valid) {
            fetch(`https://${GetParentResourceName()}/moveBagItem`, {
                method: 'POST',
                body: JSON.stringify({ bagSlot: draggedItem.slot, x: dropSlot.x, y: dropSlot.y })
            }).catch(() => {});
        }
    } else if (dragSource === 'player' && dropSlot) {
        if (isBagMode) {
            const valid = !checkBagCollision(dropSlot.x, dropSlot.y, size.w, size.h, bagInventoryData?.items || []);
            if (valid) {
                fetch(`https://${GetParentResourceName()}/moveToBag`, {
                    method: 'POST',
                    body: JSON.stringify({ playerSlot: draggedItem.slot, bagX: dropSlot.x, bagY: dropSlot.y })
                }).catch(() => {});
            }
        } else {
            fetch(`https://${GetParentResourceName()}/dropItem`, {
                method: 'POST',
                body: JSON.stringify({
                    name: draggedItem.name,
                    count: draggedItem.count || 1,
                    slot: draggedItem.slot,
                    x: dropSlot.x,
                    y: dropSlot.y
                })
            }).catch(() => {});
        }
    } else if (dragSource === 'ground' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || []);
        if (valid) {
            fetch(`https://${GetParentResourceName()}/pickupItem`, {
                method: 'POST',
                body: JSON.stringify({
                    groundSlot: draggedItem.slot,
                    x: playerSlot.x,
                    y: playerSlot.y
                })
            }).catch(() => {});
        }
    }

    cancelDrag();
}

const contextConnector = document.getElementById('context-connector');
const playersSubmenu = document.getElementById('players-submenu');
const playersList = document.getElementById('players-list');
let nearbyPlayers = [];
let contextItemElement = null;

function showContextMenu(e, item, source, itemEl) {
    e.preventDefault();
    e.stopPropagation();

    if (source !== 'player' && source !== 'bag') return;

    const useOption  = contextMenu.querySelector('[data-action="use"]');
    const dropOption = contextMenu.querySelector('[data-action="drop"]');
    const giveOption = contextMenu.querySelector('[data-action="give"]');

    if (source === 'bag') {
        if (useOption)  { useOption.querySelector('span').textContent  = 'Take'; useOption.style.display  = ''; }
        if (dropOption) { dropOption.style.display = 'none'; }
        if (giveOption) { giveOption.style.display = 'none'; }
    } else {
        if (useOption)  { useOption.querySelector('span').textContent  = 'Use';  useOption.style.display  = ''; }
        if (dropOption) { dropOption.style.display = ''; }
        if (giveOption) { giveOption.style.display = ''; }
    }

    selectedItem = { ...item, source };
    contextItemElement = itemEl;

    const itemRect = itemEl.getBoundingClientRect();

    // Position at the bottom-right corner
    const menuX = itemRect.right;
    const menuY = itemRect.bottom;

    contextMenu.style.left = menuX + 'px';
    contextMenu.style.top = menuY + 'px';
    contextMenu.classList.remove('hidden');

    playersSubmenu.classList.add('hidden');

    fetch(`https://${GetParentResourceName()}/getNearbyPlayers`, {
        method: 'POST',
        body: JSON.stringify({})
    }).catch(() => { });
}

function hideContextMenu() {
    contextMenu.classList.add('hidden');
    playersSubmenu.classList.add('hidden');
    selectedItem = null;
    contextItemElement = null;
}

contextMenu.querySelectorAll('.menu-option').forEach((option) => {
    option.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();

        if (!selectedItem) return;

        const action = option.dataset.action;
        if (action === 'use' && selectedItem.source === 'bag') {
            fetch(`https://${GetParentResourceName()}/moveFromBag`, {
                method: 'POST',
                body: JSON.stringify({ bagSlot: selectedItem.slot, playerX: null, playerY: null })
            }).catch(() => {});
            hideContextMenu();
        } else if (action === 'use') {
            fetch(`https://${GetParentResourceName()}/useItem`, {
                method: 'POST',
                body: JSON.stringify({
                    name: selectedItem.name,
                    slot: selectedItem.slot
                })
            }).catch(() => {});
            hideContextMenu();
        } else if (action === 'drop') {
            fetch(`https://${GetParentResourceName()}/dropItem`, {
                method: 'POST',
                body: JSON.stringify({
                    name: selectedItem.name,
                    count: selectedItem.count || 1,
                    slot: selectedItem.slot,
                    x: selectedItem.x || 1,
                    y: selectedItem.y || 1
                })
            }).catch(() => {});
            hideContextMenu();
        } else if (action === 'give') {
            playersSubmenu.classList.toggle('hidden');
        }
    });
});

function updateNearbyPlayers(players) {
    nearbyPlayers = players || [];
    renderPlayersList();
}

function renderPlayersList() {
    playersList.innerHTML = '';

    if (nearbyPlayers.length === 0) {
        playersList.innerHTML = '<div class="no-players">No players nearby</div>';
        return;
    }

    nearbyPlayers.forEach(player => {
        const playerEl = document.createElement('div');
        playerEl.className = 'player-option';
        const distanceText = player.distance < 1 ? '<1m' : `${Math.floor(player.distance)}m`;
        const infoDiv = document.createElement('div');
        infoDiv.className = 'player-info';
        const icon = document.createElement('i');
        icon.className = 'fa-solid fa-user';
        infoDiv.appendChild(icon);
        const nameSpan = document.createElement('span');
        nameSpan.className = 'player-name';
        nameSpan.textContent = player.name;
        infoDiv.appendChild(nameSpan);
        playerEl.appendChild(infoDiv);
        const distSpan = document.createElement('span');
        distSpan.className = 'player-distance';
        distSpan.textContent = distanceText;
        playerEl.appendChild(distSpan);
        playerEl.addEventListener('click', () => giveItemToPlayer(player.id));
        playersList.appendChild(playerEl);
    });
}

function giveItemToPlayer(playerId) {
    if (!selectedItem) return;

    console.log('[INVENTORY-JS] Giving item to player:', playerId, selectedItem.name);
    hideContextMenu();

    fetch(`https://${GetParentResourceName()}/giveItem`, {
        method: 'POST',
        body: JSON.stringify({
            name: selectedItem.name,
            count: selectedItem.count,
            slot: selectedItem.slot,
            targetPlayer: playerId
        })
    });

    hideContextMenu();
}

window.addEventListener('message', (event) => {
    const data = event.data;
    switch (data.action) {
        case 'open':
            openInventory(data.inventory || data);
            break;
        case 'update':
            updateInventory(data.inventory || data);
            break;
        case 'close':
            forceClose();
            break;
        case 'updateGround':
            updateGroundItems(data.items || []);
            break;
        case 'updateNearbyPlayers':
            updateNearbyPlayers(data.players || []);
            break;
        case 'updateHotbar':
            // Update hotbar using full inventory data (works even when inventory is closed)
            if (data.inventory) {
                // Store items and itemsData globally
                if (data.inventory.items) {
                    window.latestInventoryItems = data.inventory.items;
                }
                if (data.inventory.itemsData) {
                    itemsData = data.inventory.itemsData;
                }
                // Update hotbar display
                if (window.latestInventoryItems) {
                    assignHotkeysToSlots(window.latestInventoryItems);
                }
            }
            break;
        case 'openLootContainer':
            openLootContainer(data);
            break;
        case 'closeLootContainer':
            closeLootContainer();
            break;
        case 'openBag':
            openBag(data.bag);
            break;
        case 'syncBag':
            syncBag(data);
            break;
    }
});

function forceClose() {
    if (isContainerMode) closeLootContainer();
    if (isBagMode) closeBagMode();
    container.classList.add('hidden');
    if (typeof window.forceCloseVehicleShop === 'function') {
        window.forceCloseVehicleShop();
    } else if (vehicleShopContainer) {
        vehicleShopContainer.classList.add('hidden');
    }
    hideContextMenu();
    hideDragPreview();
    if (isDragging) cancelDrag();
}

const hotbarContainer = document.getElementById('hotbar-container');
let hotbarData = {};

function setupHotbarDragAndDrop() {
    const hotbarSlots = document.querySelectorAll('.hotbar-slot');

    hotbarSlots.forEach(slot => {
        slot.addEventListener('mouseenter', () => {
            if (isDragging && dragSource === 'player') {
                slot.classList.add('drag-over');
            }
        });

        slot.addEventListener('mouseleave', () => {
            slot.classList.remove('drag-over');
        });

        slot.addEventListener('mouseup', (e) => {
            if (!isDragging || !draggedItem || dragSource !== 'player') return;

            e.stopPropagation();
            slot.classList.remove('drag-over');

            const slotNumber = parseInt(slot.dataset.slot);
            const itemDef = itemsData[draggedItem.name] || {};

            hotbarData[slotNumber] = {
                name: draggedItem.name,
                slot: draggedItem.slot,
                data: draggedItem
            };

            fetch(`https://${GetParentResourceName()}/setHotbarSlot`, {
                method: 'POST',
                body: JSON.stringify({
                    slot: slotNumber,
                    item: hotbarData[slotNumber]
                })
            });

            renderHotbarSlot(slot, hotbarData[slotNumber], itemDef);

            cancelDrag();
        });

        slot.addEventListener('contextmenu', (e) => {
            e.preventDefault();
            const slotNumber = parseInt(slot.dataset.slot);

            if (hotbarData[slotNumber]) {
                delete hotbarData[slotNumber];

                fetch(`https://${GetParentResourceName()}/clearHotbarSlot`, {
                    method: 'POST',
                    body: JSON.stringify({ slot: slotNumber })
                });

                clearHotbarSlot(slot);
            }
        });
    });
}

function renderHotbarSlot(slot, item, itemDef) {
    const existingImg = slot.querySelector('.hotbar-item-image');
    const existingCount = slot.querySelector('.hotbar-item-count');
    const existingRarity = slot.querySelector('.hotbar-rarity-bar');

    if (existingImg) existingImg.remove();
    if (existingCount) existingCount.remove();
    if (existingRarity) existingRarity.remove();

    slot.className = 'hotbar-slot has-item';

    if (!item) return;

    const rarity = itemDef.rarity || 'common';
    slot.dataset.rarity = rarity;

    const img = document.createElement('img');
    img.className = 'hotbar-item-image';
    const row = item.data || item;
    img.src = getItemImageSrc(row, itemDef);
    img.alt = itemDef.label || item.name;
    img.onerror = function () {
        this.onerror = null;
        this.src = 'images/default.png';
    };

    const count = document.createElement('span');
    count.className = 'hotbar-item-count';
    count.textContent = item.data?.count || 1;

    const rarityBar = document.createElement('div');
    rarityBar.className = 'hotbar-rarity-bar rarity-' + rarity;

    slot.appendChild(img);
    slot.appendChild(count);
    slot.appendChild(rarityBar);
}

function clearHotbarSlot(slot) {
    const img = slot.querySelector('.hotbar-item-image');
    const count = slot.querySelector('.hotbar-item-count');
    const rarityBar = slot.querySelector('.hotbar-rarity-bar');

    if (img) img.remove();
    if (count) count.remove();
    if (rarityBar) rarityBar.remove();

    slot.className = 'hotbar-slot';
    delete slot.dataset.rarity;
}

function updateHotbar(hotbar) {
    hotbarData = hotbar || {};

    const hotbarSlots = document.querySelectorAll('.hotbar-slot');
    hotbarSlots.forEach(slot => {
        const slotNumber = parseInt(slot.dataset.slot);
        const item = hotbarData[slotNumber];

        if (item) {
            const itemDef = itemsData[item.name] || {};
            renderHotbarSlot(slot, item, itemDef);
        } else {
            clearHotbarSlot(slot);
        }
    });
}

function GetParentResourceName() {
    if (window.location.hostname === '') {
        return 'corex-inventory';
    }
    // Remove 'cfx-nui-' prefix that FiveM adds. Cached so we don't pay the
    // string-replace cost on every fetch (called from drag/drop, hotbar, etc).
    if (!GetParentResourceName._cached) {
        GetParentResourceName._cached = window.location.hostname.replace('cfx-nui-', '');
    }
    return GetParentResourceName._cached;
}

setupHotbarDragAndDrop();
initializeUI();

/* ========== BAG MODE ========== */

function renderBagWeightSegments() {
    bagWeightSegmentsContainer.innerHTML = '';

    // Scale segment count to available header space
    // header reserved: icon(42) + title(65) + weight-text(90) + paddings(28) ≈ 225px
    // each segment = 6px + 2px gap = 8px
    const gridWidth  = bagGridCols * (CONFIG.cellSize + CONFIG.gapSize) - CONFIG.gapSize;
    const panelWidth = Math.max(gridWidth + 20, 260);
    const segCount   = Math.max(4, Math.floor((panelWidth - 225) / 8));

    const frag = document.createDocumentFragment();
    for (let i = 0; i < segCount; i++) {
        const seg = document.createElement('div');
        seg.className = 'weight-segment';
        frag.appendChild(seg);
    }
    bagWeightSegmentsContainer.appendChild(frag);
}

function updateBagWeightBar(current, max) {
    const segments = bagWeightSegmentsContainer.querySelectorAll('.weight-segment');
    const percentage = Math.min((current / (max || 1)) * 100, 100);
    const filled = Math.round((percentage / 100) * segments.length);

    segments.forEach((seg, i) => {
        seg.classList.remove('filled', 'warning', 'danger');
        if (i < filled) {
            if (percentage >= 90)      seg.classList.add('danger');
            else if (percentage >= 70) seg.classList.add('warning');
            else                       seg.classList.add('filled');
        }
    });

    document.getElementById('bag-current-weight').textContent = Math.round(current * 100) / 100;
    document.getElementById('bag-max-weight').textContent = Math.round(max);
}

function checkBagCollision(x, y, w, h, items, excludeSlot) {
    if (x < 1 || y < 1 || x + w - 1 > bagGridCols || y + h - 1 > bagGridRows) return true;
    for (const item of items) {
        if (item.slot === excludeSlot) continue;
        const def = itemsData[item.name] || { size: { w: 1, h: 1 } };
        const iW = def.size?.w || 1;
        const iH = def.size?.h || 1;
        const overlapsX = !((x + w - 1) < item.x || x > (item.x + iW - 1));
        const overlapsY = !((y + h - 1) < item.y || y > (item.y + iH - 1));
        if (overlapsX && overlapsY) return true;
    }
    return false;
}

function renderBagItems() {
    dropGrid.querySelectorAll('.item').forEach(el => el.remove());
    if (!bagInventoryData || !bagInventoryData.items) return;

    const savedCols = CONFIG.gridCols;
    const savedRows = CONFIG.gridRows;
    CONFIG.gridCols = bagGridCols;
    CONFIG.gridRows = bagGridRows;

    const frag = document.createDocumentFragment();
    bagInventoryData.items.forEach(item => {
        frag.appendChild(createItemElement(item, 'bag'));
    });
    dropGrid.appendChild(frag);

    CONFIG.gridCols = savedCols;
    CONFIG.gridRows = savedRows;
}

function openBag(data) {
    if (!data) return;
    isBagMode = true;
    bagInventoryData = data;
    bagGridCols = data.gridW || 4;
    bagGridRows = data.gridH || 3;

    const dropTitle = document.getElementById('drop-title');
    const dropHint  = document.getElementById('drop-hint');
    const dropIcon  = document.getElementById('drop-icon');
    const shopMoney = document.getElementById('shop-money');
    const dropPanel = document.querySelector('.drop-panel');

    dropTitle.textContent = 'Big Bag';
    dropIcon.className    = 'fa-solid fa-bag-shopping hex-inner-icon';
    dropHint.classList.add('hidden');
    shopMoney.classList.add('hidden');
    bagWeightSegmentsContainer.classList.remove('hidden');
    bagWeightText.classList.remove('hidden');

    // Size the panel to the bag grid, with a floor so the header always fits
    // header reserved ≈ 220px (icon + title + weight-text + paddings)
    // Each extra col adds (cellSize + gapSize) = 70px
    const gridWidth  = bagGridCols * (CONFIG.cellSize + CONFIG.gapSize) - CONFIG.gapSize;
    const panelWidth = Math.max(gridWidth + 20, 260);
    if (dropPanel) {
        dropPanel.style.alignSelf = 'flex-start';
        dropPanel.style.width     = panelWidth + 'px';
        dropPanel.style.minWidth  = 'unset';
    }

    renderSlots(dropGrid, bagGridCols, bagGridRows);
    renderBagWeightSegments();
    updateBagWeightBar(data.weight || 0, data.maxWeight || 20);
    renderBagItems();
}

function syncBag(data) {
    if (!isBagMode || !bagInventoryData) return;
    bagInventoryData.items     = data.items     || [];
    bagInventoryData.weight    = data.weight    || 0;
    bagInventoryData.maxWeight = data.maxWeight || 20;
    updateBagWeightBar(bagInventoryData.weight, bagInventoryData.maxWeight);
    renderBagItems();
}

function closeBagMode() {
    isBagMode = false;
    bagInventoryData = null;

    const dropTitle = document.getElementById('drop-title');
    const dropHint  = document.getElementById('drop-hint');
    const dropIcon  = document.getElementById('drop-icon');

    dropTitle.textContent = 'Ground';
    dropIcon.className    = 'fa-solid fa-arrow-down hex-inner-icon';
    dropHint.classList.remove('hidden');
    bagWeightSegmentsContainer.classList.add('hidden');
    bagWeightText.classList.add('hidden');

    const dropPanel = document.querySelector('.drop-panel');
    if (dropPanel) {
        dropPanel.style.alignSelf = '';
        dropPanel.style.width     = '';
        dropPanel.style.minWidth  = '';
    }

    renderSlots(dropGrid, CONFIG.gridCols, CONFIG.gridRows);
    renderGroundItems();
}

/* ========== LOOT CONTAINER MODE ========== */

let isContainerMode = false;
let containerData = null;
let revealTimers = [];

function playRevealSound() {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.frequency.setValueAtTime(800, ctx.currentTime);
        osc.frequency.exponentialRampToValueAtTime(1200, ctx.currentTime + 0.05);
        osc.frequency.exponentialRampToValueAtTime(600, ctx.currentTime + 0.15);
        gain.gain.setValueAtTime(0.15, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.2);
        osc.start(ctx.currentTime);
        osc.stop(ctx.currentTime + 0.2);
    } catch (e) {}
}

function openLootContainer(data) {
    isContainerMode = true;
    containerData = data;

    const dropTitle = document.getElementById('drop-title');
    const dropHint = document.getElementById('drop-hint');
    const dropIcon = document.getElementById('drop-icon');
    const shopMoney = document.getElementById('shop-money');

    dropTitle.textContent = data.containerName || 'Loot Container';
    dropHint.classList.add('hidden');
    shopMoney.classList.add('hidden');
    dropIcon.className = 'fa-solid fa-box-open hex-inner-icon';

    const dropGridEl = document.getElementById('drop-grid');
    dropGridEl.querySelectorAll('.item').forEach(el => el.remove());

    if (!data.items || data.items.length === 0) return;

    data.items.forEach((item, index) => {
        const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 }, label: item.name, weight: 0 };
        const w = itemDef.size?.w || 1;
        const h = itemDef.size?.h || 1;
        const rarity = itemDef.rarity || item.rarity || 'common';

        const x = item.x || ((index % CONFIG.gridCols) + 1);
        const y = item.y || (Math.floor(index / CONFIG.gridCols) + 1);

        const left = (x - 1) * (CONFIG.cellSize + CONFIG.gapSize);
        const top = (y - 1) * (CONFIG.cellSize + CONFIG.gapSize);
        const width = w * CONFIG.cellSize + (w - 1) * CONFIG.gapSize;
        const height = h * CONFIG.cellSize + (h - 1) * CONFIG.gapSize;

        const el = document.createElement('div');
        el.className = `item rarity-${rarity} loot-pending`;
        el.style.left = left + 'px';
        el.style.top = top + 'px';
        el.style.width = width + 'px';
        el.style.height = height + 'px';
        el.dataset.containerIndex = index;
        el.dataset.source = 'container';
        el.dataset.name = item.name;
        el.dataset.count = item.count || 1;
        el.dataset.revealed = 'false';
        el.style.pointerEvents = 'none';

        const imgSrc = getItemImageSrc(item, itemDef);
        const totalWeight = ((itemDef.weight || 0) * (item.count || 1)).toFixed(2);

        el.innerHTML = '';
        const lootFrag = document.createDocumentFragment();
        const lr = document.createElement('span');
        lr.className = 'item-rarity';
        lr.textContent = rarity.toUpperCase();
        lootFrag.appendChild(lr);
        const lq = document.createElement('span');
        lq.className = 'item-qty';
        lq.textContent = item.count || 1;
        lootFrag.appendChild(lq);
        const lw = document.createElement('span');
        lw.className = 'item-weight';
        lw.textContent = totalWeight + 'kg';
        lootFrag.appendChild(lw);
        const lImg = document.createElement('img');
        lImg.src = imgSrc;
        lImg.alt = itemDef.label || item.name || '';
        lImg.onerror = function() { this.onerror = null; this.src = 'images/default.png'; };
        lootFrag.appendChild(lImg);
        const lName = document.createElement('span');
        lName.className = 'item-name';
        lName.textContent = item.label || itemDef.label || item.name;
        lootFrag.appendChild(lName);
        el.appendChild(lootFrag);

        const shimmer = document.createElement('div');
        shimmer.className = 'loot-shimmer';
        el.appendChild(shimmer);

        el.addEventListener('click', () => {
            if (el.dataset.revealed !== 'true') return;
            if (el.dataset.taken === 'true') return;
            el.dataset.taken = 'true';

            fetch(`https://${GetParentResourceName()}/takeLootItem`, {
                method: 'POST',
                body: JSON.stringify({
                    containerId: containerData?.containerId,
                    itemIndex: item.index != null ? item.index : index,
                    itemName: item.name,
                    itemCount: item.count || 1
                })
            }).catch(() => {});

            el.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
            el.style.opacity = '0';
            el.style.transform = 'scale(0.5)';
            setTimeout(() => el.remove(), 300);
        });

        dropGridEl.appendChild(el);

        const revealDelay = (data.revealDelay || 1800) * (index + 1);
        const timer = setTimeout(() => {
            el.classList.add('loot-revealing');
            shimmer.classList.add('revealing');

            setTimeout(() => {
                shimmer.remove();
                el.classList.remove('loot-pending', 'loot-revealing');
                el.classList.add('loot-revealed');
                el.dataset.revealed = 'true';
                el.style.pointerEvents = 'auto';
                playRevealSound();
            }, 600);
        }, revealDelay);

        revealTimers.push(timer);
    });
}

function closeLootContainer() {
    isContainerMode = false;
    containerData = null;
    revealTimers.forEach(t => clearTimeout(t));
    revealTimers = [];

    const dropTitle = document.getElementById('drop-title');
    const dropHint = document.getElementById('drop-hint');
    const dropIcon = document.getElementById('drop-icon');

    dropTitle.textContent = 'Ground';
    dropHint.classList.remove('hidden');
    dropIcon.className = 'fa-solid fa-arrow-down hex-inner-icon';
}

