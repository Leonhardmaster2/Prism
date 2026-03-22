import { Editor, rootCtx, defaultValueCtx, editorViewCtx, serializerCtx, commandsCtx, parserCtx } from '@milkdown/kit/core';
import { commonmark, toggleStrongCommand, toggleEmphasisCommand, toggleInlineCodeCommand, wrapInBlockquoteCommand, wrapInBulletListCommand, wrapInOrderedListCommand, wrapInHeadingCommand, turnIntoTextCommand, insertHrCommand, createCodeBlockCommand, sinkListItemCommand, liftListItemCommand, toggleLinkCommand, updateLinkCommand } from '@milkdown/kit/preset/commonmark';
import { gfm, toggleStrikethroughCommand, insertTableCommand, addColAfterCommand, addColBeforeCommand, addRowAfterCommand, addRowBeforeCommand, deleteSelectedCellsCommand, selectTableCommand, columnResizingPlugin, tableEditingPlugin, strikethroughInputRule } from '@milkdown/kit/preset/gfm';
import { deleteTable, deleteColumn, deleteRow, toggleHeaderRow, isInTable, columnResizing, tableEditing } from '@milkdown/kit/prose/tables';

// Filter out column resizing and table editing plugins that cause WebKit rendering floods
var gfmFiltered = gfm.filter(function(plugin) {
    // Check all possible locations for the plugin name
    var name = '';
    if (plugin && plugin.meta) name = plugin.meta.displayName || '';
    if (!name && plugin && plugin.plugin && plugin.plugin.meta) name = plugin.plugin.meta.displayName || '';
    // Also check by reference equality to the exported symbols
    if (plugin === columnResizingPlugin) return false;
    if (plugin === tableEditingPlugin) return false;
    if (plugin === strikethroughInputRule) return false;
    // Filter by name
    if (name.indexOf('columnResizing') >= 0) return false;
    if (name.indexOf('tableEditing') >= 0) return false;
    return true;
});
import { history, undoCommand, redoCommand } from '@milkdown/kit/plugin/history';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { clipboard } from '@milkdown/kit/plugin/clipboard';
import { trailing } from '@milkdown/kit/plugin/trailing';
import { indent } from '@milkdown/kit/plugin/indent';
import { math, mathBlockSchema, mathInlineSchema } from '@milkdown/plugin-math';
import { $prose, $nodeSchema, $remark } from '@milkdown/kit/utils';
import { Plugin, PluginKey, TextSelection, AllSelection } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
// Slice import removed — no longer needed for paste handler
import { keymap } from '@milkdown/kit/prose/keymap';
import { toggleMark } from '@milkdown/kit/prose/commands';

// ─── Ready guard ───────────────────────────────────────
var hasNotifiedReady = false;

// ─── Bridge: JS → Swift ────────────────────────────────
var globalMuteUntil = 0;
function sendToSwift(action, data) {
    // Allow certain actions through always; mute state/content updates after commands
    var alwaysAllow = (action === 'ready' || action === 'fetchVideoMeta' || action === 'openURL' || action === 'jslog' || action === 'save' || action === 'requestLink');
    if (!alwaysAllow && Date.now() < globalMuteUntil) return;
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.prism) {
        window.webkit.messageHandlers.prism.postMessage(JSON.stringify({ action, data }));
    }
}

// ─── Word count ────────────────────────────────────────
function countWords(text) {
    return text.split(/\s+/).filter(function(w) { return w.length > 0; }).length;
}

// ─── State tracking ────────────────────────────────────
function getEditorState(editorView) {
    var state = editorView.state;
    var sel = state.selection;
    var from = sel.from;
    var to = sel.to;
    var empty = sel.empty;
    var resolvedPos = state.doc.resolve(from);

    var storedMarks = state.storedMarks || resolvedPos.marks();
    var markTypes = storedMarks.map(function(m) { return m.type.name; });

    var isBold = markTypes.indexOf('strong') >= 0;
    var isItalic = markTypes.indexOf('emphasis') >= 0;
    var isInlineCode = markTypes.indexOf('inlineCode') >= 0;
    var isStrikethrough = markTypes.indexOf('strikethrough') >= 0;

    var parentNode = resolvedPos.parent;
    var nodeName = parentNode.type.name;

    var headingLevel = 0;
    if (nodeName === 'heading') {
        headingLevel = parentNode.attrs.level || 0;
    }

    var isInList = false;
    var listType = null;
    var isInBlockquote = false;
    var isInCodeBlock = nodeName === 'code_block';

    for (var depth = resolvedPos.depth; depth > 0; depth--) {
        var ancestor = resolvedPos.node(depth);
        var name = ancestor.type.name;
        if (name === 'bullet_list') { isInList = true; listType = 'bullet'; }
        if (name === 'ordered_list') { isInList = true; listType = 'ordered'; }
        if (name === 'blockquote') { isInBlockquote = true; }
    }

    var hasSelection = !empty;
    var selectedText = '';
    if (hasSelection) {
        selectedText = state.doc.textBetween(from, to, ' ');
    }

    return {
        isBold: isBold, isItalic: isItalic, isInlineCode: isInlineCode, isStrikethrough: isStrikethrough,
        headingLevel: headingLevel,
        isInList: isInList, listType: listType, isInBlockquote: isInBlockquote, isInCodeBlock: isInCodeBlock,
        hasSelection: hasSelection, selectedText: selectedText
    };
}

// ─── Helper: check if cursor is inside a code block ───
function isInCodeBlock(state) {
    var $from = state.selection.$from;
    for (var d = $from.depth; d >= 0; d--) {
        var name = $from.node(d).type.name;
        if (name === 'code_block' || name === 'fence') return true;
    }
    return false;
}

// ─── Throttled state change plugin ────────────────────
var stateChangeKey = new PluginKey('stateChange');
var lastStateUpdate = 0;
var stateUpdateTimer = null;
var stateChangePlugin = $prose(function() {
    return new Plugin({
        key: stateChangeKey,
        view: function() {
            return {
                update: function(view, prevState) {
                    if (isLoadingContent || isExecutingCommand) return;
                    if (view.state.selection.eq(prevState.selection) &&
                        view.state.doc.eq(prevState.doc)) return;

                    // Completely suppress state updates inside code blocks
                    try {
                        if (isInCodeBlock(view.state)) return;
                    } catch(e) {}

                    // Throttle: max 5 updates per second
                    var now = Date.now();
                    if (now - lastStateUpdate < 200) {
                        if (!stateUpdateTimer) {
                            stateUpdateTimer = setTimeout(function() {
                                stateUpdateTimer = null;
                                lastStateUpdate = Date.now();
                                try {
                                    if (isInCodeBlock(view.state)) return;
                                    var info = getEditorState(view);
                                    sendToSwift('stateChanged', info);
                                } catch(e) {}
                            }, 200);
                        }
                        return;
                    }
                    lastStateUpdate = now;
                    try {
                        var info = getEditorState(view);
                        sendToSwift('stateChanged', info);
                    } catch (e) {}
                }
            };
        }
    });
});

// ─── Custom keymap plugin ─────────────────────────────
var customKeymapPlugin = $prose(function(ctx) {
    var bindings = {};

    // Mod-Shift-x → strikethrough
    bindings['Mod-Shift-x'] = function(state, dispatch) {
        var cmds = editorInstance.ctx.get(commandsCtx);
        cmds.call(toggleStrikethroughCommand.key);
        return true;
    };

    // Mod-e → toggle inline code
    bindings['Mod-e'] = function(state, dispatch) {
        try {
            var commands = ctx.get(commandsCtx);
            commands.call(toggleInlineCodeCommand.key);
            return true;
        } catch(e) { return false; }
    };

    // Mod-1 through Mod-6 → heading levels
    for (var i = 1; i <= 6; i++) {
        (function(level) {
            bindings['Mod-' + level] = function(state, dispatch) {
                try {
                    var commands = ctx.get(commandsCtx);
                    commands.call(wrapInHeadingCommand.key, level);
                    return true;
                } catch(e) { return false; }
            };
        })(i);
    }

    // Mod-Shift-8 → bullet list
    bindings['Mod-Shift-8'] = function(state, dispatch) {
        try {
            var commands = ctx.get(commandsCtx);
            commands.call(wrapInBulletListCommand.key);
            return true;
        } catch(e) { return false; }
    };

    // Mod-Shift-7 → ordered list
    bindings['Mod-Shift-7'] = function(state, dispatch) {
        try {
            var commands = ctx.get(commandsCtx);
            commands.call(wrapInOrderedListCommand.key);
            return true;
        } catch(e) { return false; }
    };

    // Mod-Shift-. → blockquote
    bindings['Mod-Shift-.'] = function(state, dispatch) {
        try {
            var commands = ctx.get(commandsCtx);
            commands.call(wrapInBlockquoteCommand.key);
            return true;
        } catch(e) { return false; }
    };

    // Tab → sink list item (indent)
    bindings['Tab'] = function(state, dispatch) {
        try {
            var commands = ctx.get(commandsCtx);
            commands.call(sinkListItemCommand.key);
            return true;
        } catch(e) { return false; }
    };

    // Shift-Tab → lift list item (outdent)
    bindings['Shift-Tab'] = function(state, dispatch) {
        try {
            var commands = ctx.get(commandsCtx);
            commands.call(liftListItemCommand.key);
            return true;
        } catch(e) { return false; }
    };

    return keymap(bindings);
});

// ─── Floating format bar removed — handled by SwiftUI toolbar ───

// ─── Slash command menu plugin ────────────────────────
var slashMenuKey = new PluginKey('slashMenu');

var slashMenuPluginFixed = $prose(function(ctx) {
    // Shared state for the slash menu
    var menuState = {
        menu: null,
        allItems: [
            { label: 'Text', desc: 'Plain text', command: 'paragraph', icon: '\u00B6' },
            { label: 'Heading 1', desc: 'Large heading', command: 'heading', payload: { level: 1 }, icon: 'H1' },
            { label: 'Heading 2', desc: 'Medium heading', command: 'heading', payload: { level: 2 }, icon: 'H2' },
            { label: 'Heading 3', desc: 'Small heading', command: 'heading', payload: { level: 3 }, icon: 'H3' },
            { label: 'Bullet List', desc: 'Unordered list', command: 'bulletList', icon: '\u2022' },
            { label: 'Ordered List', desc: 'Numbered list', command: 'orderedList', icon: '1.' },
            { label: 'Task List', desc: 'Checklist', command: 'taskList', icon: '\u2611' },
            { label: 'Blockquote', desc: 'Quote block', command: 'blockquote', icon: '\u201C' },
            { label: 'Code Block', desc: 'Code snippet', command: 'codeBlock', icon: '\u2039\u203A' },
            { label: 'Divider', desc: 'Horizontal rule', command: 'horizontalRule', icon: '\u2014' },
            { label: 'Math Block', desc: 'Block equation', command: 'mathBlock', icon: '\u2211' },
            { label: 'Inline Math', desc: 'Inline equation', command: 'mathInline', icon: 'fx' },
            { label: 'Chemistry', desc: 'Chemical formula', command: 'chemistry', icon: '\u2697' },
            { label: 'YouTube', desc: 'Embed video', command: 'insertYouTube', icon: '\u25B6' },
            { label: 'Flashcard', desc: 'Flip card', command: 'insertFlashcard', icon: '\u2726' }
        ],
        filteredItems: [],
        selectedIndex: 0,
        slashPos: null,
        isOpen: false,
        container: null,
        editorView: null
    };

    function clearMenuChildren(el) {
        while (el.firstChild) {
            el.removeChild(el.firstChild);
        }
    }

    function renderMenu() {
        var ms = menuState;
        clearMenuChildren(ms.menu);
        ms.filteredItems.forEach(function(item, idx) {
            var el = document.createElement('div');
            el.className = 'slash-item' + (idx === ms.selectedIndex ? ' selected' : '');

            var iconSpan = document.createElement('span');
            iconSpan.className = 'slash-icon';
            iconSpan.textContent = item.icon;

            var labelSpan = document.createElement('span');
            labelSpan.textContent = item.label;

            el.appendChild(iconSpan);
            el.appendChild(labelSpan);

            el.addEventListener('mousedown', function(e) {
                e.preventDefault();
                e.stopPropagation();
                selectItem(idx);
            });

            ms.menu.appendChild(el);
        });

        var selectedEl = ms.menu.querySelector('.slash-item.selected');
        if (selectedEl) {
            selectedEl.scrollIntoView({ block: 'nearest' });
        }
    }

    function selectItem(idx) {
        var ms = menuState;
        if (idx < 0 || idx >= ms.filteredItems.length) return;
        var item = ms.filteredItems[idx];
        var view = ms.editorView;

        // Remove the slash and any filter text
        var state = view.state;
        var curPos = state.selection.from;
        if (ms.slashPos !== null && ms.slashPos <= curPos) {
            var tr = state.tr.delete(ms.slashPos, curPos);
            view.dispatch(tr);
        }

        closeMenu();

        // Execute the command
        if (item.command === 'taskList') {
            window.executeCommand('bulletList');
        } else {
            window.executeCommand(item.command, item.payload);
        }

        view.focus();
    }

    function openMenu(pos) {
        var ms = menuState;
        ms.slashPos = pos;
        ms.isOpen = true;
        ms.selectedIndex = 0;
        ms.filteredItems = ms.allItems.slice();
        ms.menu.style.display = 'block';
        renderMenu();
        positionMenu();
    }

    function closeMenu() {
        var ms = menuState;
        ms.isOpen = false;
        ms.slashPos = null;
        ms.menu.style.display = 'none';
    }

    function positionMenu() {
        var ms = menuState;
        try {
            var coords = ms.editorView.coordsAtPos(ms.slashPos);
            var containerRect = ms.container.getBoundingClientRect();
            var left = coords.left - containerRect.left;
            var top = coords.bottom - containerRect.top + 4;
            left = Math.max(0, Math.min(left, containerRect.width - 220));
            ms.menu.style.left = left + 'px';
            ms.menu.style.top = top + 'px';
        } catch(e) {
            // fallback positioning
        }
    }

    function filterItems(query) {
        var ms = menuState;
        var q = query.toLowerCase();
        ms.filteredItems = ms.allItems.filter(function(item) {
            return item.label.toLowerCase().indexOf(q) >= 0 ||
                   item.desc.toLowerCase().indexOf(q) >= 0;
        });
        ms.selectedIndex = Math.min(ms.selectedIndex, Math.max(0, ms.filteredItems.length - 1));
        renderMenu();
    }

    return new Plugin({
        key: slashMenuKey,
        view: function(editorView) {
            var ms = menuState;
            ms.editorView = editorView;

            var menu = document.createElement('div');
            menu.className = 'prism-slash-menu';
            menu.style.display = 'none';
            menu.setAttribute('contenteditable', 'false');
            ms.menu = menu;

            var container = editorView.dom.parentElement;
            if (container) {
                container.style.position = 'relative';
                container.appendChild(menu);
            }
            ms.container = container;

            return {
                update: function(view) {
                    ms.editorView = view;
                    if (!ms.isOpen) {
                        // Check if user just typed '/'
                        var state = view.state;
                        var sel = state.selection;
                        if (!sel.empty) return;

                        var pos = sel.from;
                        if (pos > 0) {
                            var before = state.doc.textBetween(Math.max(0, pos - 1), pos);
                            if (before === '/') {
                                var resolved = state.doc.resolve(pos);
                                var textBeforeSlash = pos > 1 ? state.doc.textBetween(Math.max(0, pos - 2), pos - 1) : '';
                                var isAtStart = ((pos - 1) === resolved.start());
                                var isAfterSpace = (textBeforeSlash === ' ' || textBeforeSlash === '\u00A0');

                                if (isAtStart || isAfterSpace) {
                                    openMenu(pos - 1);
                                }
                            }
                        }
                    } else {
                        // Menu is open: update filter
                        var state = view.state;
                        var sel = state.selection;
                        var pos = sel.from;

                        if (sel.empty && ms.slashPos !== null && pos >= ms.slashPos) {
                            var fullText = state.doc.textBetween(ms.slashPos, pos);
                            if (fullText.charAt(0) !== '/') {
                                closeMenu();
                                return;
                            }
                            var query = fullText.slice(1);
                            filterItems(query);
                            positionMenu();
                        } else {
                            closeMenu();
                        }
                    }
                },
                destroy: function() {
                    if (ms.menu && ms.menu.parentNode) ms.menu.parentNode.removeChild(ms.menu);
                }
            };
        },
        props: {
            handleKeyDown: function(view, event) {
                var ms = menuState;
                if (!ms.isOpen) return false;

                if (event.key === 'ArrowDown') {
                    event.preventDefault();
                    ms.selectedIndex = (ms.selectedIndex + 1) % ms.filteredItems.length;
                    renderMenu();
                    return true;
                }
                if (event.key === 'ArrowUp') {
                    event.preventDefault();
                    ms.selectedIndex = (ms.selectedIndex - 1 + ms.filteredItems.length) % ms.filteredItems.length;
                    renderMenu();
                    return true;
                }
                if (event.key === 'Enter') {
                    event.preventDefault();
                    selectItem(ms.selectedIndex);
                    return true;
                }
                if (event.key === 'Escape') {
                    event.preventDefault();
                    closeMenu();
                    return true;
                }
                return false;
            }
        }
    });
});

// ─── Find/Replace bar ─────────────────────────────────
var findBarKey = new PluginKey('findBar');
var findBarState = {
    bar: null,
    searchInput: null,
    replaceInput: null,
    replaceRow: null,
    matchCountEl: null,
    matches: [],
    currentMatchIndex: -1,
    query: '',
    isOpen: false,
    showReplace: false,
    editorView: null,
    closeBtn: null
};

function buildFindBar() {
    var fb = findBarState;

    var bar = document.createElement('div');
    bar.className = 'prism-find-bar';
    bar.style.display = 'none';
    bar.setAttribute('contenteditable', 'false');

    // Search row
    var searchRow = document.createElement('div');
    searchRow.className = 'prism-find-row';

    var searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.className = 'prism-find-input';
    searchInput.placeholder = 'Find...';
    searchInput.setAttribute('autocomplete', 'off');
    searchInput.setAttribute('autocorrect', 'off');
    searchInput.setAttribute('autocapitalize', 'off');
    searchInput.setAttribute('spellcheck', 'false');

    var matchCount = document.createElement('span');
    matchCount.className = 'prism-find-count';
    matchCount.textContent = '';

    var prevBtn = document.createElement('button');
    prevBtn.type = 'button';
    prevBtn.className = 'prism-find-btn';
    prevBtn.textContent = '\u2191';
    prevBtn.title = 'Previous match (Shift+Enter)';

    var nextBtn = document.createElement('button');
    nextBtn.type = 'button';
    nextBtn.className = 'prism-find-btn';
    nextBtn.textContent = '\u2193';
    nextBtn.title = 'Next match (Enter)';

    var closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'prism-find-btn prism-find-close';
    closeBtn.textContent = '\u00D7';
    closeBtn.title = 'Close (Escape)';

    searchRow.appendChild(searchInput);
    searchRow.appendChild(matchCount);
    searchRow.appendChild(prevBtn);
    searchRow.appendChild(nextBtn);
    searchRow.appendChild(closeBtn);

    // Replace row
    var replaceRow = document.createElement('div');
    replaceRow.className = 'prism-find-row prism-replace-row';
    replaceRow.style.display = 'none';

    var replaceInput = document.createElement('input');
    replaceInput.type = 'text';
    replaceInput.className = 'prism-find-input';
    replaceInput.placeholder = 'Replace...';
    replaceInput.setAttribute('autocomplete', 'off');
    replaceInput.setAttribute('autocorrect', 'off');
    replaceInput.setAttribute('autocapitalize', 'off');
    replaceInput.setAttribute('spellcheck', 'false');

    var replaceBtn = document.createElement('button');
    replaceBtn.type = 'button';
    replaceBtn.className = 'prism-find-btn prism-replace-btn';
    replaceBtn.textContent = 'Replace';

    var replaceAllBtn = document.createElement('button');
    replaceAllBtn.type = 'button';
    replaceAllBtn.className = 'prism-find-btn prism-replace-btn';
    replaceAllBtn.textContent = 'All';

    replaceRow.appendChild(replaceInput);
    replaceRow.appendChild(replaceBtn);
    replaceRow.appendChild(replaceAllBtn);

    bar.appendChild(searchRow);
    bar.appendChild(replaceRow);

    // Store references
    fb.bar = bar;
    fb.searchInput = searchInput;
    fb.replaceInput = replaceInput;
    fb.replaceRow = replaceRow;
    fb.matchCountEl = matchCount;
    fb.closeBtn = closeBtn;

    // Event handlers
    searchInput.addEventListener('input', function() {
        fb.query = searchInput.value;
        fb.currentMatchIndex = -1;
        updateFindDecorations();
        if (fb.matches.length > 0) {
            fb.currentMatchIndex = 0;
            scrollToMatch();
        }
        updateMatchCount();
    });

    searchInput.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            goToNextMatch();
        } else if (e.key === 'Enter' && e.shiftKey) {
            e.preventDefault();
            goToPrevMatch();
        } else if (e.key === 'Escape') {
            e.preventDefault();
            closeFindBar();
        }
    });

    replaceInput.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            e.preventDefault();
            closeFindBar();
        } else if (e.key === 'Enter') {
            e.preventDefault();
            doReplace();
        }
    });

    prevBtn.addEventListener('click', function(e) {
        e.preventDefault();
        goToPrevMatch();
    });

    nextBtn.addEventListener('click', function(e) {
        e.preventDefault();
        goToNextMatch();
    });

    closeBtn.addEventListener('click', function(e) {
        e.preventDefault();
        closeFindBar();
    });

    replaceBtn.addEventListener('click', function(e) {
        e.preventDefault();
        doReplace();
    });

    replaceAllBtn.addEventListener('click', function(e) {
        e.preventDefault();
        doReplaceAll();
    });

    return bar;
}

function updateMatchCount() {
    var fb = findBarState;
    if (!fb.matchCountEl) return;
    if (fb.matches.length === 0) {
        fb.matchCountEl.textContent = fb.query ? 'No results' : '';
    } else {
        fb.matchCountEl.textContent = (fb.currentMatchIndex + 1) + ' of ' + fb.matches.length;
    }
}

function goToNextMatch() {
    var fb = findBarState;
    if (fb.matches.length === 0) return;
    fb.currentMatchIndex = (fb.currentMatchIndex + 1) % fb.matches.length;
    scrollToMatch();
    updateMatchCount();
    updateFindDecorations();
}

function goToPrevMatch() {
    var fb = findBarState;
    if (fb.matches.length === 0) return;
    fb.currentMatchIndex = (fb.currentMatchIndex - 1 + fb.matches.length) % fb.matches.length;
    scrollToMatch();
    updateMatchCount();
    updateFindDecorations();
}

function scrollToMatch() {
    var fb = findBarState;
    if (fb.currentMatchIndex < 0 || fb.currentMatchIndex >= fb.matches.length) return;
    var match = fb.matches[fb.currentMatchIndex];
    var view = fb.editorView;
    if (!view) return;

    try {
        var tr = view.state.tr.setSelection(TextSelection.create(view.state.doc, match.from, match.to));
        tr.scrollIntoView();
        view.dispatch(tr);
    } catch(e) {
        // ignore
    }
}

function doReplace() {
    var fb = findBarState;
    if (fb.currentMatchIndex < 0 || fb.currentMatchIndex >= fb.matches.length) return;
    var view = fb.editorView;
    if (!view) return;

    var match = fb.matches[fb.currentMatchIndex];
    var replaceText = fb.replaceInput.value;
    var tr = view.state.tr.replaceWith(match.from, match.to, view.state.schema.text(replaceText));
    view.dispatch(tr);

    // Re-search after replacement
    fb.currentMatchIndex = Math.min(fb.currentMatchIndex, fb.matches.length - 1);
    updateFindDecorations();
    if (fb.matches.length > 0) {
        fb.currentMatchIndex = Math.min(fb.currentMatchIndex, fb.matches.length - 1);
        scrollToMatch();
    }
    updateMatchCount();
}

function doReplaceAll() {
    var fb = findBarState;
    if (fb.matches.length === 0) return;
    var view = fb.editorView;
    if (!view) return;

    var replaceText = fb.replaceInput.value;
    // Replace from end to start so positions stay valid
    var tr = view.state.tr;
    for (var i = fb.matches.length - 1; i >= 0; i--) {
        var match = fb.matches[i];
        tr.replaceWith(match.from, match.to, view.state.schema.text(replaceText));
    }
    view.dispatch(tr);

    fb.currentMatchIndex = -1;
    updateFindDecorations();
    updateMatchCount();
}

function findAllMatches(doc, query) {
    var results = [];
    if (!query) return results;

    var lowerQuery = query.toLowerCase();
    doc.descendants(function(node, pos) {
        if (node.isText) {
            var text = node.text.toLowerCase();
            var idx = 0;
            while (true) {
                var found = text.indexOf(lowerQuery, idx);
                if (found < 0) break;
                results.push({ from: pos + found, to: pos + found + query.length });
                idx = found + 1;
            }
        }
    });
    return results;
}

function updateFindDecorations() {
    var fb = findBarState;
    var view = fb.editorView;
    if (!view) return;

    fb.matches = findAllMatches(view.state.doc, fb.query);

    // Dispatch a transaction with meta to trigger decoration recomputation
    var tr = view.state.tr.setMeta(findBarKey, { updated: true });
    view.dispatch(tr);
}

function closeFindBar() {
    var fb = findBarState;
    fb.isOpen = false;
    fb.query = '';
    fb.matches = [];
    fb.currentMatchIndex = -1;
    if (fb.bar) fb.bar.style.display = 'none';
    if (fb.searchInput) fb.searchInput.value = '';
    if (fb.replaceInput) fb.replaceInput.value = '';
    updateFindDecorations();
    if (fb.editorView) fb.editorView.focus();
}

window.showFindBar = function(withReplace) {
    var fb = findBarState;
    fb.isOpen = true;
    fb.showReplace = !!withReplace;

    if (fb.bar) {
        fb.bar.style.display = 'block';
    }
    if (fb.replaceRow) {
        fb.replaceRow.style.display = withReplace ? 'flex' : 'none';
    }
    if (fb.searchInput) {
        fb.searchInput.focus();
        fb.searchInput.select();
    }
};

var findBarPlugin = $prose(function() {
    return new Plugin({
        key: findBarKey,
        view: function(editorView) {
            var fb = findBarState;
            fb.editorView = editorView;

            var bar = buildFindBar();
            var container = editorView.dom.parentElement;
            if (container) {
                container.style.position = 'relative';
                container.appendChild(bar);
            }

            return {
                update: function(view) {
                    fb.editorView = view;
                },
                destroy: function() {
                    if (fb.bar && fb.bar.parentNode) fb.bar.parentNode.removeChild(fb.bar);
                }
            };
        },
        state: {
            init: function() {
                return DecorationSet.empty;
            },
            apply: function(tr, oldDecos, oldState, newState) {
                var fb = findBarState;
                if (!fb.isOpen || !fb.query) return DecorationSet.empty;

                // Recompute if doc changed or meta flag set
                if (tr.docChanged || tr.getMeta(findBarKey)) {
                    fb.matches = findAllMatches(newState.doc, fb.query);
                    var decos = fb.matches.map(function(m, idx) {
                        var cls = 'prism-find-match';
                        if (idx === fb.currentMatchIndex) {
                            cls += ' prism-find-match-current';
                        }
                        return Decoration.inline(m.from, m.to, { class: cls });
                    });
                    return DecorationSet.create(newState.doc, decos);
                }

                return oldDecos.map(tr.mapping, tr.doc);
            }
        },
        props: {
            decorations: function(state) {
                return findBarKey.getState(state);
            },
            handleKeyDown: function(view, event) {
                // Mod+F → find
                if ((event.metaKey || event.ctrlKey) && event.key === 'f' && !event.shiftKey) {
                    event.preventDefault();
                    window.showFindBar(false);
                    return true;
                }
                // Mod+Shift+F or Mod+H → find and replace
                if ((event.metaKey || event.ctrlKey) && ((event.key === 'f' && event.shiftKey) || event.key === 'h')) {
                    event.preventDefault();
                    window.showFindBar(true);
                    return true;
                }
                return false;
            }
        }
    });
});

// ─── Scroll tracking ──────────────────────────────────
var scrollTimeout;
function setupScrollTracking() {
    window.addEventListener('scroll', function() {
        clearTimeout(scrollTimeout);
        scrollTimeout = setTimeout(function() {
            sendToSwift('scrollChanged', { position: window.scrollY });
        }, 200);
    }, { passive: true });
}

// ─── Content change debounce ──────────────────────────
var contentChangeTimer;
function scheduleContentChange(editor) {
    clearTimeout(contentChangeTimer);
    // Use longer debounce inside code blocks to prevent feedback loops
    var delay = 1000;
    try {
        var view = editor.ctx.get(editorViewCtx);
        if (isInCodeBlock(view.state)) delay = 2500;
    } catch(e) {}
    contentChangeTimer = setTimeout(function() {
        try {
            var ctx = editor.ctx;
            var serializer = ctx.get(serializerCtx);
            var view = ctx.get(editorViewCtx);
            var markdown = serializer(view.state.doc);
            var wordCount = countWords(markdown);
            sendToSwift('contentChanged', { markdown: markdown, wordCount: wordCount });
        } catch (e) {
            console.error('[Prism] Failed to serialize content:', e);
        }
    }, delay);
}

// ─── Table toolbar plugin ─────────────────────────────
var tableToolbarKey = new PluginKey('tableToolbar');
var tableToolbarPlugin = $prose(function(ctx) {
    return new Plugin({
        key: tableToolbarKey,
        view: function(editorView) {
            var bar = document.createElement('div');
            bar.className = 'prism-table-toolbar';
            bar.style.display = 'none';
            bar.setAttribute('contenteditable', 'false');

            // Prevent focus stealing
            bar.addEventListener('mousedown', function(e) { e.preventDefault(); });

            // ── Row 1: Structure ──
            var row1 = document.createElement('div');
            row1.className = 'tt-row';
            [
                { icon: '\u2191', cmd: 'addRowBefore', tip: 'Row above' },
                { icon: '\u2193', cmd: 'addRowAfter', tip: 'Row below' },
                { icon: '\u2190', cmd: 'addColBefore', tip: 'Col left' },
                { icon: '\u2192', cmd: 'addColAfter', tip: 'Col right' }
            ].forEach(function(a) {
                row1.appendChild(makeBtn(a.icon, a.tip, function() { tableAction(a.cmd, editorView); }));
            });
            bar.appendChild(row1);

            // ── Row 2: Style toggles ──
            var row2 = document.createElement('div');
            row2.className = 'tt-row';
            var toggles = { header: false, striped: false, borders: false, outline: false };
            ['Header', 'Striped', 'Borders', 'Outline'].forEach(function(label) {
                var key = label.toLowerCase();
                var btn = document.createElement('button');
                btn.type = 'button';
                btn.textContent = label;
                btn.className = 'tt-toggle';
                btn.addEventListener('mousedown', function(e) {
                    e.preventDefault(); e.stopPropagation();
                    toggles[key] = !toggles[key];
                    btn.classList.toggle('active', toggles[key]);
                    applyToggles(editorView, toggles);
                    // Show/hide color row
                    if (key === 'header') row3.style.display = toggles.header ? 'flex' : 'none';
                });
                row2.appendChild(btn);
            });
            bar.appendChild(row2);

            // ── Row 3: Header colors (hidden by default) ──
            var row3 = document.createElement('div');
            row3.className = 'tt-row';
            row3.style.display = 'none';
            ['', 'blue', 'green', 'purple', 'orange'].forEach(function(color) {
                var dot = document.createElement('button');
                dot.type = 'button';
                dot.className = 'tt-color';
                dot.title = color || 'Default';
                if (color) {
                    var colors = { blue: '#4A90D9', green: '#34C759', purple: '#AF52DE', orange: '#FF9500' };
                    dot.style.background = colors[color] || '#6E7681';
                } else {
                    dot.style.background = '#6E7681';
                }
                dot.addEventListener('mousedown', function(e) {
                    e.preventDefault(); e.stopPropagation();
                    tableAction('color:' + color, editorView);
                });
                row3.appendChild(dot);
            });
            bar.appendChild(row3);

            // ── Row 4: Danger ──
            var row4 = document.createElement('div');
            row4.className = 'tt-row';
            [
                { text: 'Del Row', cmd: 'deleteRow' },
                { text: 'Del Col', cmd: 'deleteCol' },
                { text: 'Del Table', cmd: 'deleteTable' }
            ].forEach(function(a) {
                var btn = document.createElement('button');
                btn.type = 'button';
                btn.textContent = a.text;
                btn.className = 'tt-danger';
                btn.addEventListener('mousedown', function(e) {
                    e.preventDefault(); e.stopPropagation();
                    tableAction(a.cmd, editorView);
                });
                row4.appendChild(btn);
            });
            bar.appendChild(row4);

            var container = editorView.dom.parentElement;
            if (container) {
                container.style.position = 'relative';
                container.appendChild(bar);
            }

            var hideTimer = null;

            return {
                update: function(view) {
                    if (isLoadingContent || isExecutingCommand) return;
                    var inTbl = false;
                    try { inTbl = isInTable(view.state); } catch(e) {}

                    if (!inTbl) {
                        if (!hideTimer) {
                            hideTimer = setTimeout(function() {
                                bar.style.display = 'none';
                                hideTimer = null;
                            }, 300);
                        }
                        return;
                    }
                    if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
                    bar.style.display = 'block';

                    // Re-apply toggles on every update (DOM may have been re-rendered)
                    applyToggles(view, toggles);

                    try {
                        var $pos = view.state.selection.$from;
                        for (var d = $pos.depth; d > 0; d--) {
                            if ($pos.node(d).type.name === 'table') {
                                var coords = view.coordsAtPos($pos.before(d));
                                var cr = container.getBoundingClientRect();
                                bar.style.left = Math.max(0, coords.left - cr.left) + 'px';
                                bar.style.top = Math.max(0, coords.top - cr.top - bar.offsetHeight - 8) + 'px';
                                break;
                            }
                        }
                    } catch(e) {}
                },
                destroy: function() {
                    if (bar.parentNode) bar.parentNode.removeChild(bar);
                }
            };
        }
    });
});

function setTableAttr(view, attr, value) {
    try {
        var $p = view.state.selection.$from;
        for (var d = $p.depth; d > 0; d--) {
            if ($p.node(d).type.name === 'table') {
                var dom = view.nodeDOM($p.before(d));
                if (dom) {
                    var current = dom.getAttribute(attr);
                    if (current === value) {
                        dom.removeAttribute(attr);
                    } else {
                        dom.setAttribute(attr, value);
                    }
                }
                break;
            }
        }
    } catch(e) {}
}

function makeBtn(text, title, onclick) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = text;
    btn.title = title;
    btn.addEventListener('mousedown', function(e) {
        e.preventDefault(); e.stopPropagation();
        onclick();
    });
    return btn;
}

function applyToggles(view, toggles) {
    try {
        var $p = view.state.selection.$from;
        for (var d = $p.depth; d > 0; d--) {
            if ($p.node(d).type.name === 'table') {
                var dom = view.nodeDOM($p.before(d));
                if (dom) {
                    dom.setAttribute('data-header', toggles.header);
                    dom.setAttribute('data-striped', toggles.striped);
                    dom.setAttribute('data-borders', toggles.borders);
                    dom.setAttribute('data-outline', toggles.outline);
                }
                break;
            }
        }
    } catch(e) {}
}

function tableAction(cmd, view) {
    globalMuteUntil = Date.now() + 500;
    isExecutingCommand = true;
    setTimeout(function() {
        try {
            var commands = editorInstance.ctx.get(commandsCtx);
            var curView = editorInstance.ctx.get(editorViewCtx);
            switch(cmd) {
                case 'addRowBefore': commands.call(addRowBeforeCommand.key); break;
                case 'addRowAfter': commands.call(addRowAfterCommand.key); break;
                case 'addColBefore': commands.call(addColBeforeCommand.key); break;
                case 'addColAfter': commands.call(addColAfterCommand.key); break;
                case 'deleteRow': deleteRow(curView.state, curView.dispatch); break;
                case 'deleteCol': deleteColumn(curView.state, curView.dispatch); break;
                case 'deleteTable': deleteTable(curView.state, curView.dispatch); break;
                default:
                    if (cmd.indexOf('color:') === 0) {
                        var color = cmd.split(':')[1];
                        setTableAttr(curView, 'data-color', color);
                    }
            }
        } catch(e) {
            console.warn('[TABLE]', cmd, e.message);
        } finally {
            isExecutingCommand = false;
        }
    }, 0);
}

// ─── Checkbox click handler plugin ────────────────────
var checkboxPluginKey = new PluginKey('checkboxClick');
var checkboxPlugin = $prose(function() {
    return new Plugin({
        key: checkboxPluginKey,
        props: {
            handleClick: function(view, pos, event) {
                // Check if clicked on a list item with data-checked attribute
                var $pos = view.state.doc.resolve(pos);
                for (var d = $pos.depth; d >= 0; d--) {
                    var node = $pos.node(d);
                    if (node.type.name === 'list_item' && node.attrs.checked !== null && node.attrs.checked !== undefined) {
                        var nodePos = $pos.before(d);
                        var attrs = Object.assign({}, node.attrs);
                        attrs.checked = !attrs.checked;
                        var tr = view.state.tr.setNodeMarkup(nodePos, null, attrs);
                        view.dispatch(tr);
                        return true;
                    }
                }
                return false;
            }
        }
    });
});

// Math trailing strut removed — was breaking text selection

// Math auto-detect removed — was scanning entire doc on every keystroke,
// causing cursor/selection issues. Math input rules handle typed math.
// Pasted math is handled by the paste plugin.

// ─── Math node view plugin (click-to-edit) ────────────
var mathNodeViewPlugin = $prose(function(ctx) {
    return new Plugin({
        key: new PluginKey('mathNodeView'),
        props: {
            nodeViews: {
                math_inline: function(node, view, getPos) {
                    return createMathNodeView(node, view, getPos, 'inline', ctx);
                },
                math_block: function(node, view, getPos) {
                    return createMathNodeView(node, view, getPos, 'block', ctx);
                }
            }
        }
    });
});

function measureTextWidth(text, font) {
    var m = document.createElement('span');
    m.style.cssText = 'visibility:hidden;position:absolute;white-space:pre;font:' + (font || 'inherit');
    m.textContent = text || ' ';
    document.body.appendChild(m);
    var w = m.offsetWidth;
    m.remove();
    return w;
}

function createMathNodeView(node, view, getPos, mode, ctx) {
    var dom = document.createElement(mode === 'inline' ? 'span' : 'div');
    dom.className = 'math-node-' + (mode === 'inline' ? 'inline' : 'display');
    if (mode === 'block') {
        dom.setAttribute('contenteditable', 'false');
    }
    // For inline: use CSS -webkit-user-modify: read-only instead of contenteditable="false"
    // This prevents WebKit's caret positioning bug at contenteditable boundaries
    var innerWrap = dom;

    var rendered = document.createElement(mode === 'inline' ? 'span' : 'div');
    rendered.className = 'math-rendered';

    var input;
    if (mode === 'block') {
        input = document.createElement('textarea');
        input.className = 'math-src math-src-block';
        input.rows = 2;
    } else {
        input = document.createElement('input');
        input.type = 'text';
        input.className = 'math-src';
    }
    input.style.display = 'none';

    innerWrap.appendChild(rendered);
    innerWrap.appendChild(input);

    var latex = mode === 'block' ? (node.attrs.value || '') : node.textContent;

    function renderMath() {
        try {
            if (typeof katex !== 'undefined' && latex) {
                katex.render(latex, rendered, {
                    displayMode: mode === 'block',
                    throwOnError: false,
                    trust: true
                });
            } else {
                rendered.textContent = latex || (mode === 'block' ? 'Click to add math' : '$');
            }
        } catch(e) {
            rendered.textContent = latex;
        }
        rendered.style.display = '';
        input.style.display = 'none';
    }

    function resizeInput() {
        if (mode !== 'inline') return;
        var font = '15px "SF Mono", "Menlo", monospace';
        var w = measureTextWidth(input.value || ' ', font);
        input.style.width = Math.max(w + 24, 60) + 'px';
    }

    function showInput() {
        input.value = latex;
        rendered.style.display = 'none';
        input.style.display = '';
        resizeInput();
        input.focus();
        input.select();
    }

    function exitNode(direction) {
        commitEdit();
        // Move cursor outside the math node
        if (typeof getPos === 'function') {
            var pos = getPos();
            if (pos !== undefined) {
                var targetPos = direction === 'right' ? pos + node.nodeSize : pos;
                try {
                    var sel = TextSelection.near(view.state.doc.resolve(targetPos), direction === 'right' ? 1 : -1);
                    view.dispatch(view.state.tr.setSelection(sel));
                    view.focus();
                } catch(e) {}
            }
        }
    }

    renderMath();

    dom.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        showInput();
    });

    input.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && (mode === 'inline' || !e.shiftKey)) {
            e.preventDefault();
            commitEdit();
            return;
        }
        if (e.key === 'Escape') {
            e.preventDefault();
            renderMath();
            view.focus();
            return;
        }
        if (e.key === 'Tab') {
            e.preventDefault();
            exitNode('right');
            return;
        }

        // Arrow key exit: left at position 0, right at end
        if (mode === 'inline') {
            if (e.key === 'ArrowLeft' && input.selectionStart === 0 && input.selectionEnd === 0) {
                e.preventDefault();
                exitNode('left');
                return;
            }
            if (e.key === 'ArrowRight' && input.selectionStart === input.value.length && input.selectionEnd === input.value.length) {
                e.preventDefault();
                exitNode('right');
                return;
            }
        }

        // Resize on content change
        if (mode === 'inline') {
            setTimeout(resizeInput, 0);
        }
    });

    input.addEventListener('input', function() {
        if (mode === 'inline') resizeInput();
    });

    input.addEventListener('blur', function() {
        commitEdit();
    });

    function commitEdit() {
        var newLatex = input.value.trim();
        if (newLatex !== latex && typeof getPos === 'function') {
            latex = newLatex;
            globalMuteUntil = Date.now() + 500;
            var pos = getPos();
            if (pos !== undefined) {
                var tr = view.state.tr;
                if (mode === 'block') {
                    tr.setNodeMarkup(pos, null, { value: newLatex });
                } else {
                    var nodeSize = node.nodeSize;
                    var newNode = view.state.schema.nodes.math_inline.create(
                        null,
                        newLatex ? view.state.schema.text(newLatex) : null
                    );
                    tr.replaceWith(pos, pos + nodeSize, newNode);
                }
                view.dispatch(tr);
            }
        } else if (!newLatex && latex) {
            // User cleared the input — keep old value
            latex = latex;
        }
        renderMath();
        view.focus();
    }

    return {
        dom: dom,
        update: function(updatedNode) {
            if (mode === 'inline' && updatedNode.type.name !== 'math_inline') return false;
            if (mode === 'block' && updatedNode.type.name !== 'math_block') return false;
            node = updatedNode;
            latex = mode === 'block' ? (updatedNode.attrs.value || '') : updatedNode.textContent;
            if (input.style.display === 'none') renderMath();
            return true;
        },
        selectNode: function() {
            dom.classList.add('ProseMirror-selectednode');
        },
        deselectNode: function() {
            dom.classList.remove('ProseMirror-selectednode');
            if (input.style.display !== 'none') commitEdit();
        },
        stopEvent: function(e) {
            return dom.contains(e.target);
        },
        ignoreMutation: function() {
            return true;
        },
        destroy: function() {}
    };
}

// ─── Safe paste handler for complex content ───────────
// Mute ALL bridge messages and set flags to suppress plugins during paste.
// ─── Unified paste handler ────────────────────────────
// Single plugin handles ALL paste logic with clear priority:
// 1. Single-line YouTube URL → create embed
// 2. Complex/large content → mute bridge, let ProseMirror handle
// 3. Everything else → let ProseMirror handle normally
var unifiedPastePlugin = $prose(function(ctx) {
    return new Plugin({
        key: new PluginKey('unifiedPaste'),
        props: {
            handlePaste: function(view, event) {
                var text = event.clipboardData && event.clipboardData.getData('text/plain');
                if (!text) return false;
                var trimmed = text.trim();

                // Priority 1: Single-line YouTube URL or markdown image-link → create embed
                if (trimmed.indexOf('\n') === -1 && trimmed.length < 300) {
                    // Also match [![...](img)](youtube-url) format
                    var vid = extractYouTubeId(trimmed);
                    if (vid) {
                        globalMuteUntil = Date.now() + 500;
                        var nodeType = view.state.schema.nodes.youtube_video;
                        if (nodeType) {
                            var ytNode = nodeType.create({ videoId: vid });
                            view.dispatch(view.state.tr.replaceSelectionWith(ytNode));
                            sendToSwift('fetchVideoMeta', { videoId: vid });
                            return true;
                        }
                    }
                }

                // Priority 2: Multi-line content → use loadContent for proper markdown parsing
                // ProseMirror's default paste inserts as plain text — it won't parse markdown
                // syntax like $math$, tables, or code blocks. We need Milkdown's parser.
                var lines = text.split('\n');
                if (lines.length > 3 || text.length > 200) {
                    globalMuteUntil = Date.now() + 5000;
                    isLoadingContent = true;
                    isExecutingCommand = true;

                    try {
                        var serializer = editorInstance.ctx.get(serializerCtx);
                        var curView = editorInstance.ctx.get(editorViewCtx);
                        var currentMd = serializer(curView.state.doc);
                        var newMd = currentMd + '\n\n' + text;

                        // Defer the reload to avoid WebKit flood
                        setTimeout(function() {
                            window.loadContent(newMd);
                            setTimeout(function() {
                                isLoadingContent = false;
                                isExecutingCommand = false;
                            }, 2000);
                        }, 100);
                    } catch(e) {
                        isLoadingContent = false;
                        isExecutingCommand = false;
                        return false;
                    }
                    return true;
                }

                // Small single-line pastes: let ProseMirror handle
                return false;
            }
        }
    });
});

// ─── YouTube video embedding ──────────────────────────

function extractYouTubeId(url) {
    var patterns = [
        /youtube\.com\/watch\?v=([a-zA-Z0-9_-]{11})/,
        /youtu\.be\/([a-zA-Z0-9_-]{11})/,
        /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/,
        /youtube\.com\/embed\/([a-zA-Z0-9_-]{11})/
    ];
    for (var i = 0; i < patterns.length; i++) {
        var m = url.match(patterns[i]);
        if (m) return m[1];
    }
    return null;
}

// YouTube node schema
var youtubeVideoSchema = $nodeSchema('youtube_video', function() {
    return {
        group: 'block',
        atom: true,
        isolating: true,
        attrs: {
            videoId: { default: '' },
            title: { default: '' },
            author: { default: '' }
        },
        parseDOM: [{
            tag: 'div[data-youtube-video]',
            getAttrs: function(dom) {
                return {
                    videoId: dom.getAttribute('data-video-id') || '',
                    title: dom.getAttribute('data-title') || '',
                    author: dom.getAttribute('data-author') || ''
                };
            }
        }],
        toDOM: function(node) {
            return ['div', {
                'data-youtube-video': '',
                'data-video-id': node.attrs.videoId,
                'data-title': node.attrs.title,
                'data-author': node.attrs.author,
                'class': 'youtube-embed'
            }];
        },
        parseMarkdown: {
            match: function(node) { return node.type === 'youtube_video'; },
            runner: function(state, node, type) {
                state.addNode(type, { videoId: node.videoId || '', title: node.title || '', author: node.author || '' });
            }
        },
        toMarkdown: {
            match: function(node) { return node.type.name === 'youtube_video'; },
            runner: function(state, node) {
                // Serialize as a simple URL on its own line
                state.addNode('paragraph', undefined, 'https://www.youtube.com/watch?v=' + node.attrs.videoId);
            }
        }
    };
});

// YouTube node view
var youtubeNodeViewPlugin = $prose(function() {
    return new Plugin({
        key: new PluginKey('youtubeNodeView'),
        props: {
            nodeViews: {
                youtube_video: function(node, view, getPos) {
                    return createYouTubeNodeView(node, view, getPos);
                }
            }
        }
    });
});

function createYouTubeNodeView(node, view, getPos) {
    var dom = document.createElement('div');
    dom.className = 'youtube-embed';
    dom.setAttribute('contenteditable', 'false');
    var playing = false;
    var videoId = node.attrs.videoId;

    // Block native context menu on the entire embed
    dom.addEventListener('contextmenu', function(e) {
        e.preventDefault();
        e.stopPropagation();
        showYTContextMenu(e.clientX, e.clientY);
    });

    function renderThumbnail() {
        var title = node.attrs.title || '';
        var author = node.attrs.author || '';

        dom.textContent = '';

        var container = document.createElement('div');
        container.className = 'youtube-thumb-container';

        var img = document.createElement('img');
        img.className = 'youtube-thumb';
        img.src = 'https://img.youtube.com/vi/' + videoId + '/maxresdefault.jpg';
        img.onerror = function() { img.src = 'https://img.youtube.com/vi/' + videoId + '/hqdefault.jpg'; };
        container.appendChild(img);

        // Gradient overlay at bottom for text readability
        var gradient = document.createElement('div');
        gradient.className = 'youtube-gradient';
        container.appendChild(gradient);

        // Play button — blue frosted circle
        var playBtn = document.createElement('div');
        playBtn.className = 'youtube-play-btn';
        playBtn.textContent = '\u25B6';
        container.appendChild(playBtn);

        // Info overlay on bottom of thumbnail
        var overlay = document.createElement('div');
        overlay.className = 'youtube-overlay';

        if (title) {
            var titleEl = document.createElement('div');
            titleEl.className = 'youtube-title';
            titleEl.textContent = title;
            overlay.appendChild(titleEl);
        }

        var meta = document.createElement('div');
        meta.className = 'youtube-meta';
        var badge = document.createElement('span');
        badge.className = 'youtube-badge';
        badge.textContent = 'YOUTUBE';
        meta.appendChild(badge);
        if (author) {
            var authorEl = document.createElement('span');
            authorEl.className = 'youtube-author';
            authorEl.textContent = author;
            meta.appendChild(authorEl);
        }
        overlay.appendChild(meta);
        container.appendChild(overlay);

        dom.appendChild(container);

        // Left click → play inline
        container.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            playInline();
        });

        // Right click → context menu
        container.addEventListener('contextmenu', function(e) {
            e.preventDefault();
            e.stopPropagation();
            showYTContextMenu(e.clientX, e.clientY);
        });
    }

    function playInline() {
        // Replace thumbnail with YouTube iframe — works because editor loads via http://localhost
        var playerContainer = document.createElement('div');
        playerContainer.className = 'youtube-player-container';
        var iframe = document.createElement('iframe');
        iframe.className = 'youtube-iframe';
        iframe.src = 'https://www.youtube.com/embed/' + videoId + '?autoplay=1&rel=0&modestbranding=1&playsinline=1';
        iframe.setAttribute('frameborder', '0');
        iframe.setAttribute('allowfullscreen', '');
        iframe.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture');
        playerContainer.appendChild(iframe);

        // Keep info bar, replace thumb with player
        var thumb = dom.querySelector('.youtube-thumb-container');
        if (thumb) {
            thumb.replaceWith(playerContainer);
        } else {
            dom.textContent = '';
            dom.appendChild(playerContainer);
        }
    }

    function showYTContextMenu(x, y) {
        // Remove existing menu
        var old = document.getElementById('yt-context-menu');
        if (old) old.remove();

        var menu = document.createElement('div');
        menu.id = 'yt-context-menu';
        menu.className = 'yt-context-menu';
        menu.style.left = x + 'px';
        menu.style.top = y + 'px';

        var items = [
            { label: 'Open in Browser', action: function() { sendToSwift('openURL', { url: 'https://www.youtube.com/watch?v=' + videoId }); } },
            { label: 'Copy URL', action: function() { navigator.clipboard.writeText('https://www.youtube.com/watch?v=' + videoId).catch(function(){}); } },
            { label: 'Edit URL', action: function() {
                // Show inline input for editing URL
                var inputDiv = document.createElement('div');
                inputDiv.className = 'yt-url-edit';
                inputDiv.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:10000;background:var(--code-bg);border:1px solid var(--code-border);border-radius:10px;padding:16px;box-shadow:0 8px 32px rgba(0,0,0,0.2);width:400px;';
                var label = document.createElement('div');
                label.textContent = 'YouTube URL:';
                label.style.cssText = 'font-size:13px;color:var(--text-secondary);margin-bottom:8px;';
                var inp = document.createElement('input');
                inp.type = 'text';
                inp.value = 'https://www.youtube.com/watch?v=' + videoId;
                inp.style.cssText = 'width:100%;padding:8px;border:1px solid var(--code-border);border-radius:6px;background:var(--bg);color:var(--text);font-size:14px;outline:none;box-sizing:border-box;';
                var btns = document.createElement('div');
                btns.style.cssText = 'display:flex;gap:8px;justify-content:flex-end;margin-top:12px;';
                var cancelBtn = document.createElement('button');
                cancelBtn.textContent = 'Cancel';
                cancelBtn.style.cssText = 'padding:6px 14px;border:1px solid var(--code-border);border-radius:6px;background:transparent;color:var(--text);cursor:pointer;font-size:13px;';
                var saveBtn = document.createElement('button');
                saveBtn.textContent = 'Save';
                saveBtn.style.cssText = 'padding:6px 14px;border:none;border-radius:6px;background:var(--accent);color:white;cursor:pointer;font-size:13px;';

                inputDiv.appendChild(label);
                inputDiv.appendChild(inp);
                btns.appendChild(cancelBtn);
                btns.appendChild(saveBtn);
                inputDiv.appendChild(btns);
                document.body.appendChild(inputDiv);
                inp.focus();
                inp.select();

                function doSave() {
                    var newId = extractYouTubeId(inp.value.trim());
                    if (newId && typeof getPos === 'function') {
                        globalMuteUntil = Date.now() + 500;
                        var pos = getPos();
                        view.dispatch(view.state.tr.setNodeMarkup(pos, null, { videoId: newId, title: '', author: '' }));
                        sendToSwift('fetchVideoMeta', { videoId: newId });
                    }
                    inputDiv.remove();
                }
                function doCancel() { inputDiv.remove(); }

                saveBtn.addEventListener('click', doSave);
                cancelBtn.addEventListener('click', doCancel);
                inp.addEventListener('keydown', function(e) {
                    if (e.key === 'Enter') doSave();
                    if (e.key === 'Escape') doCancel();
                });
            }},
            { sep: true },
            { label: 'Revert to URL', action: function() {
                if (typeof getPos === 'function') {
                    globalMuteUntil = Date.now() + 500;
                    var pos = getPos();
                    var p = view.state.schema.nodes.paragraph.create(null, view.state.schema.text('https://www.youtube.com/watch?v=' + videoId));
                    view.dispatch(view.state.tr.replaceWith(pos, pos + node.nodeSize, p));
                }
            }},
            { label: 'Delete', action: function() {
                if (typeof getPos === 'function') {
                    globalMuteUntil = Date.now() + 500;
                    var pos = getPos();
                    view.dispatch(view.state.tr.delete(pos, pos + node.nodeSize));
                }
            }}
        ];

        items.forEach(function(item) {
            if (item.sep) {
                var sep = document.createElement('div');
                sep.className = 'yt-menu-sep';
                menu.appendChild(sep);
                return;
            }
            var btn = document.createElement('div');
            btn.className = 'yt-menu-item';
            btn.textContent = item.label;
            btn.addEventListener('mousedown', function(e) {
                e.preventDefault();
                item.action();
                menu.remove();
            });
            menu.appendChild(btn);
        });

        document.body.appendChild(menu);
        // Close on click outside
        setTimeout(function() {
            document.addEventListener('mousedown', function closeMenu(e) {
                if (!menu.contains(e.target)) { menu.remove(); document.removeEventListener('mousedown', closeMenu); }
            });
        }, 10);
    }

    renderThumbnail();

    // Request metadata from Swift
    if (!node.attrs.title) {
        sendToSwift('fetchVideoMeta', { videoId: videoId });
    }

    return {
        dom: dom,
        update: function(updatedNode) {
            if (updatedNode.type.name !== 'youtube_video') return false;
            node = updatedNode;
            videoId = node.attrs.videoId;
            if (!playing) renderThumbnail();
            return true;
        },
        selectNode: function() { dom.classList.add('ProseMirror-selectednode'); },
        deselectNode: function() { dom.classList.remove('ProseMirror-selectednode'); },
        stopEvent: function(e) {
            // Only stop events when the math input is visible (editing mode)
            // Let mouse events through so text selection across math nodes works
            if (input.style.display !== 'none') {
                return innerWrap.contains(e.target);
            }
            return false;
        },
        ignoreMutation: function() { return true; },
        destroy: function() {}
    };
}

// Callback from Swift with video metadata
window.setVideoMeta = function(videoId, meta) {
    if (!editorInstance) return;
    try {
        var view = editorInstance.ctx.get(editorViewCtx);
        view.state.doc.descendants(function(node, pos) {
            if (node.type.name === 'youtube_video' && node.attrs.videoId === videoId) {
                var tr = view.state.tr.setNodeMarkup(pos, null, {
                    videoId: videoId,
                    title: meta.title || '',
                    author: meta.author || ''
                });
                view.dispatch(tr);
                return false;
            }
        });
    } catch(e) {
        console.warn('[YT] setVideoMeta error:', e.message);
    }
};

// YouTube paste handler removed — merged into unifiedPastePlugin

// ─── YouTube auto-detect (appendTransaction) ─────────
// Scans for YouTube URLs on their own line and converts to youtube_video nodes
// YouTube auto-detect removed from appendTransaction — was causing cursor issues.
// YouTube URLs are detected on paste (youtubePastePlugin) and on load (post-load scan in loadContent).

// ─── Flashcard remark plugin ──────────────────────────

// Helper: extract all text from an mdast paragraph node, preserving $...$ for math
function mdastParaText(node) {
    if (!node || !node.children) return '';
    var t = '';
    for (var i = 0; i < node.children.length; i++) {
        var child = node.children[i];
        if (child.type === 'inlineMath') {
            t += '$' + (child.value || '') + '$';
        } else if (child.value) {
            t += child.value;
        } else if (child.children) {
            t += mdastParaText(child);
        }
    }
    return t;
}

// Parse the opening tag: :::flashcard or :::flashcard[SetName] or :::flashcard[SetName] Question
// Returns { set: string, question: string } or null if not a flashcard tag
function parseFlashcardTag(text) {
    if (text.indexOf(':::flashcard') !== 0) return null;
    var rest = text.slice(':::flashcard'.length);
    var set = '';
    // Check for [SetName] immediately after :::flashcard
    if (rest.charAt(0) === '[') {
        var closeIdx = rest.indexOf(']');
        if (closeIdx > 1) {
            set = rest.slice(1, closeIdx);
            rest = rest.slice(closeIdx + 1);
        }
    }
    var question = rest.trim();
    return { set: set, question: question };
}

function remarkFlashcardPlugin() {
    return function(tree) {
        var children = tree.children;
        if (!children) return;
        var newChildren = [];
        var i = 0;
        while (i < children.length) {
            var node = children[i];

            // Primary detection: paragraph nodes starting with :::flashcard
            if (node.type === 'paragraph' && node.children && node.children.length > 0) {
                var fullText = mdastParaText(node).trim();
                var parsed = parseFlashcardTag(fullText);

                if (parsed) {
                    var afterTag = parsed.question;
                    var question = '';
                    var answer = '';
                    var foundEnd = false;

                    // Format A: :::flashcard Question\nAnswer ::: (question on same line, ::: closes inline)
                    // Format B: :::flashcard\nQuestion\n---\nAnswer\n::: (fenced with --- separator)
                    // Format C: :::flashcard Question\nAnswer\n::: (::: on its own line)

                    if (afterTag) {
                        // Question is on the opening line (after ":::flashcard ")
                        question = afterTag;
                        // Check if the closing ::: is also in the same paragraph (single-paragraph card)
                        if (question.indexOf(' :::') >= 0 && question.lastIndexOf(' :::') === question.length - 4) {
                            // e.g. ":::flashcard Q\nA :::" all in one paragraph — won't happen in remark
                        }
                    }

                    // Scan ahead for content and closing :::
                    var j = i + 1;
                    var phase = afterTag ? 'answer' : 'question'; // if Q was on opening line, go straight to answer
                    while (j < children.length) {
                        var c2 = children[j];

                        // --- separator: switch from question to answer phase
                        if (c2.type === 'thematicBreak' && phase === 'question') {
                            phase = 'answer';
                            j++;
                            continue;
                        }

                        if (c2.type === 'paragraph' && c2.children) {
                            var txt = mdastParaText(c2).trim();

                            // Check for closing ::: at end of text (inline close)
                            if (txt === ':::') {
                                foundEnd = true;
                                break;
                            }
                            if (txt.length > 4 && txt.lastIndexOf(' :::') === txt.length - 4) {
                                // Text ends with " :::" — extract content before it
                                var content = txt.slice(0, txt.length - 4).trim();
                                if (phase === 'question') {
                                    question += (question ? '\n' : '') + content;
                                } else {
                                    answer += (answer ? '\n' : '') + content;
                                }
                                foundEnd = true;
                                break;
                            }
                            if (txt.endsWith(':::') && txt.length > 3) {
                                // Text ends with ":::" (no space) — e.g. "answer text.:::"
                                var content2 = txt.slice(0, txt.length - 3).trim();
                                if (content2) {
                                    if (phase === 'question') {
                                        question += (question ? '\n' : '') + content2;
                                    } else {
                                        answer += (answer ? '\n' : '') + content2;
                                    }
                                }
                                foundEnd = true;
                                break;
                            }

                            // Regular content paragraph
                            if (phase === 'question') {
                                question += (question ? '\n' : '') + txt;
                            } else {
                                answer += (answer ? '\n' : '') + txt;
                            }
                        }
                        j++;
                    }

                    if (foundEnd && (question || answer)) {
                        newChildren.push({
                            type: 'flashcard',
                            question: question || 'Question',
                            answer: answer || 'Answer',
                            set: parsed.set || ''
                        });
                        i = j + 1;
                        continue;
                    }
                }
            }

            // Also detect when remark parses ":::flashcard Question" as a heading
            // (remark-parse does not do this, but some preprocessors might)
            if (node.type === 'heading' && node.children && node.children.length > 0) {
                var hText = mdastParaText(node).trim();
                var hParsed = parseFlashcardTag(hText);
                if (hParsed) {
                    var hQuestion = hParsed.question;
                    var hAnswer = '';
                    var hFoundEnd = false;
                    var hj = i + 1;
                    while (hj < children.length) {
                        var hc = children[hj];
                        if (hc.type === 'paragraph' && hc.children) {
                            var ht = mdastParaText(hc).trim();
                            if (ht === ':::') { hFoundEnd = true; break; }
                            if (ht.endsWith(' :::')) {
                                hAnswer += (hAnswer ? '\n' : '') + ht.slice(0, -4).trim();
                                hFoundEnd = true; break;
                            }
                            if (ht.endsWith(':::') && ht.length > 3) {
                                hAnswer += (hAnswer ? '\n' : '') + ht.slice(0, -3).trim();
                                hFoundEnd = true; break;
                            }
                            hAnswer += (hAnswer ? '\n' : '') + ht;
                        } else if (hc.type === 'thematicBreak') {
                            // skip --- separators
                        }
                        hj++;
                    }
                    if (hFoundEnd) {
                        newChildren.push({
                            type: 'flashcard',
                            question: hQuestion || 'Question',
                            answer: hAnswer || 'Answer',
                            set: hParsed.set || ''
                        });
                        i = hj + 1;
                        continue;
                    }
                }
            }

            newChildren.push(node);
            i++;
        }
        tree.children = newChildren;
    };
}

var remarkFlashcard = $remark('remarkFlashcard', function() {
    return remarkFlashcardPlugin;
});

// ─── Flashcard node schema ────────────────────────────

var flashcardSchema = $nodeSchema('flashcard', function() {
    return {
        group: 'block',
        atom: true,
        isolating: true,
        attrs: {
            question: { default: 'Question' },
            answer: { default: 'Answer' },
            set: { default: '' }
        },
        parseDOM: [{
            tag: 'div[data-type="flashcard"]',
            getAttrs: function(dom) {
                return {
                    question: dom.getAttribute('data-question') || 'Question',
                    answer: dom.getAttribute('data-answer') || 'Answer',
                    set: dom.getAttribute('data-set') || ''
                };
            }
        }],
        toDOM: function(node) {
            var attrs = {
                'data-type': 'flashcard',
                'data-question': node.attrs.question,
                'data-answer': node.attrs.answer,
                'class': 'flashcard-block'
            };
            if (node.attrs.set) attrs['data-set'] = node.attrs.set;
            return ['div', attrs];
        },
        parseMarkdown: {
            match: function(node) { return node.type === 'flashcard'; },
            runner: function(state, node, type) {
                state.addNode(type, {
                    question: node.question || 'Question',
                    answer: node.answer || 'Answer',
                    set: node.set || ''
                });
            }
        },
        toMarkdown: {
            match: function(node) { return node.type.name === 'flashcard'; },
            runner: function(state, node) {
                var tag = ':::flashcard';
                if (node.attrs.set) tag += '[' + node.attrs.set + ']';
                state.addNode('html', undefined,
                    tag + '\n' + node.attrs.question + '\n---\n' + node.attrs.answer + '\n:::');
            }
        }
    };
});

// ─── Flashcard node view ──────────────────────────────

// Stack management: groups adjacent flashcard DOM elements
var flashcardStackState = {
    timer: null,
    // Scan the editor DOM and group adjacent .flashcard-block elements
    refresh: function() {
        if (flashcardStackState.timer) clearTimeout(flashcardStackState.timer);
        flashcardStackState.timer = setTimeout(function() {
            flashcardStackState._doRefresh();
        }, 50);
    },
    _doRefresh: function() {
        var editor = document.querySelector('.ProseMirror');
        if (!editor) return;
        var children = editor.children;
        var i = 0;
        while (i < children.length) {
            var el = children[i];
            if (el.classList.contains('flashcard-block')) {
                // Find the run of adjacent flashcard blocks
                var stack = [el];
                var j = i + 1;
                while (j < children.length && children[j].classList.contains('flashcard-block')) {
                    stack.push(children[j]);
                    j++;
                }
                if (stack.length > 1) {
                    // Find which card was previously visible (preserve navigation state)
                    var activeIdx = 0;
                    for (var s = 0; s < stack.length; s++) {
                        if (stack[s].classList.contains('flashcard-stack-visible')) {
                            activeIdx = s;
                            break;
                        }
                    }
                    // Clamp in case stack shrank
                    if (activeIdx >= stack.length) activeIdx = 0;
                    // Mark all as part of a stack
                    for (var s = 0; s < stack.length; s++) {
                        stack[s].setAttribute('data-stack-size', stack.length);
                        stack[s].setAttribute('data-stack-index', s);
                        if (s === activeIdx) {
                            stack[s].classList.add('flashcard-stack-visible');
                            stack[s].classList.remove('flashcard-stack-hidden');
                        } else {
                            stack[s].classList.add('flashcard-stack-hidden');
                            stack[s].classList.remove('flashcard-stack-visible');
                        }
                    }
                } else {
                    // Single card — remove stack attributes
                    el.removeAttribute('data-stack-size');
                    el.removeAttribute('data-stack-index');
                    el.classList.remove('flashcard-stack-visible', 'flashcard-stack-hidden');
                }
                i = j;
            } else {
                i++;
            }
        }
        // Trigger render of navigation on visible stack cards
        var visibles = editor.querySelectorAll('.flashcard-stack-visible');
        for (var v = 0; v < visibles.length; v++) {
            flashcardStackState._renderNav(visibles[v]);
        }
    },
    _renderNav: function(el) {
        // Remove existing nav
        var oldNav = el.querySelector('.flashcard-stack-nav');
        if (oldNav) oldNav.remove();

        var stackSize = parseInt(el.getAttribute('data-stack-size') || '1');
        var stackIndex = parseInt(el.getAttribute('data-stack-index') || '0');
        if (stackSize <= 1) return;

        var nav = document.createElement('div');
        nav.className = 'flashcard-stack-nav';

        var prevBtn = document.createElement('span');
        prevBtn.className = 'flashcard-nav-btn' + (stackIndex === 0 ? ' disabled' : '');
        prevBtn.textContent = '\u2039'; // ‹
        prevBtn.addEventListener('mousedown', function(e) { e.stopPropagation(); e.preventDefault(); });
        prevBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            if (stackIndex > 0) flashcardStackState._navigateTo(el, stackIndex - 1);
        });

        var counter = document.createElement('span');
        counter.className = 'flashcard-nav-counter';
        counter.textContent = (stackIndex + 1) + ' / ' + stackSize;

        var nextBtn = document.createElement('span');
        nextBtn.className = 'flashcard-nav-btn' + (stackIndex === stackSize - 1 ? ' disabled' : '');
        nextBtn.textContent = '\u203A'; // ›
        nextBtn.addEventListener('mousedown', function(e) { e.stopPropagation(); e.preventDefault(); });
        nextBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            if (stackIndex < stackSize - 1) flashcardStackState._navigateTo(el, stackIndex + 1);
        });

        nav.appendChild(prevBtn);
        nav.appendChild(counter);
        nav.appendChild(nextBtn);

        // Insert nav after the header
        var header = el.querySelector('.flashcard-header');
        if (header && header.nextSibling) {
            el.insertBefore(nav, header.nextSibling);
        } else {
            el.appendChild(nav);
        }
    },
    _navigateTo: function(currentEl, targetIndex) {
        // Find the stack this element belongs to
        var editor = document.querySelector('.ProseMirror');
        if (!editor) return;
        var children = editor.children;
        // Walk backward to find the start of the stack
        var startIdx = -1;
        for (var i = 0; i < children.length; i++) {
            if (children[i] === currentEl) { startIdx = i; break; }
        }
        if (startIdx < 0) return;
        // Walk backward to find first in stack
        while (startIdx > 0 && children[startIdx - 1].classList.contains('flashcard-block')) startIdx--;
        // The target element
        var targetEl = children[startIdx + targetIndex];
        if (!targetEl) return;
        // Get the stack
        var stack = [];
        var k = startIdx;
        while (k < children.length && children[k].classList.contains('flashcard-block')) {
            stack.push(children[k]);
            k++;
        }
        // Update visibility
        for (var s = 0; s < stack.length; s++) {
            stack[s].setAttribute('data-stack-index', s);
            if (s === targetIndex) {
                stack[s].classList.add('flashcard-stack-visible');
                stack[s].classList.remove('flashcard-stack-hidden');
                flashcardStackState._renderNav(stack[s]);
            } else {
                stack[s].classList.add('flashcard-stack-hidden');
                stack[s].classList.remove('flashcard-stack-visible');
                var oldNav2 = stack[s].querySelector('.flashcard-stack-nav');
                if (oldNav2) oldNav2.remove();
            }
        }
    }
};

var flashcardNodeViewPlugin = $prose(function() {
    return new Plugin({
        key: new PluginKey('flashcardNodeView'),
        props: {
            nodeViews: {
                flashcard: function(node, view, getPos) {
                    return createFlashcardNodeView(node, view, getPos);
                }
            }
        },
        view: function() {
            return {
                update: function() {
                    flashcardStackState.refresh();
                }
            };
        }
    });
});

// Render inline LaTeX ($...$) inside a DOM element using KaTeX
function renderFlashcardMath(el, text) {
    el.textContent = '';
    var parts = text.split(/(\$[^$]+\$)/g);
    for (var p = 0; p < parts.length; p++) {
        var part = parts[p];
        if (part.charAt(0) === '$' && part.charAt(part.length - 1) === '$' && part.length > 2) {
            var mathSrc = part.slice(1, -1);
            var mathSpan = document.createElement('span');
            try {
                if (window.katex) {
                    window.katex.render(mathSrc, mathSpan, { throwOnError: false, displayMode: false });
                } else {
                    mathSpan.textContent = part;
                }
            } catch(e) {
                mathSpan.textContent = part;
            }
            el.appendChild(mathSpan);
        } else if (part) {
            el.appendChild(document.createTextNode(part));
        }
    }
}

function createFlashcardNodeView(node, view, getPos) {
    var dom = document.createElement('div');
    dom.className = 'flashcard-block';
    dom.setAttribute('contenteditable', 'false');

    var flipped = false;
    var editMode = false;
    var currentQuestion = node.attrs.question;
    var currentAnswer = node.attrs.answer;
    var currentSet = node.attrs.set || '';

    var frontContent = null;
    var backContent = null;
    var setInput = null;

    function render() {
        dom.textContent = '';

        // Header
        var header = document.createElement('div');
        header.className = 'flashcard-header';
        var icon = document.createElement('span');
        icon.className = 'flashcard-icon';
        icon.textContent = '\u2726';
        var label = document.createElement('span');
        label.className = 'flashcard-label';
        label.textContent = 'Flashcard';
        header.appendChild(icon);
        header.appendChild(label);

        // Edit toggle button
        var editBtn = document.createElement('span');
        editBtn.className = 'flashcard-edit-btn' + (editMode ? ' active' : '');
        editBtn.textContent = editMode ? 'Done' : 'Edit';
        header.appendChild(editBtn);

        // Set badge (only in edit mode)
        var setBadge = document.createElement('span');
        setBadge.className = 'flashcard-set-badge';
        if (editMode) {
            setBadge.setAttribute('contenteditable', 'true');
        }
        setBadge.setAttribute('data-placeholder', 'Set');
        setBadge.textContent = currentSet;
        header.appendChild(setBadge);
        setInput = setBadge;

        dom.appendChild(header);

        // Card container
        var card = document.createElement('div');
        card.className = 'flashcard-card';
        card.setAttribute('data-flipped', flipped ? 'true' : 'false');

        var inner = document.createElement('div');
        inner.className = 'flashcard-inner';

        // Front face (Question)
        var front = document.createElement('div');
        front.className = 'flashcard-face flashcard-front';
        var frontLabel = document.createElement('span');
        frontLabel.className = 'flashcard-face-label';
        frontLabel.textContent = 'QUESTION';
        frontContent = document.createElement('div');
        frontContent.className = 'flashcard-content';
        if (editMode) {
            frontContent.setAttribute('contenteditable', 'true');
            frontContent.textContent = currentQuestion;
        } else {
            renderFlashcardMath(frontContent, currentQuestion);
        }
        front.appendChild(frontLabel);
        front.appendChild(frontContent);

        // Back face (Answer)
        var back = document.createElement('div');
        back.className = 'flashcard-face flashcard-back';
        var backLabel = document.createElement('span');
        backLabel.className = 'flashcard-face-label';
        backLabel.textContent = 'ANSWER';
        backContent = document.createElement('div');
        backContent.className = 'flashcard-content';
        if (editMode) {
            backContent.setAttribute('contenteditable', 'true');
            backContent.textContent = currentAnswer;
        } else {
            renderFlashcardMath(backContent, currentAnswer);
        }
        back.appendChild(backLabel);
        back.appendChild(backContent);

        inner.appendChild(front);
        inner.appendChild(back);
        card.appendChild(inner);

        // Flip hint (only in study mode)
        if (!editMode) {
            var hint = document.createElement('div');
            hint.className = 'flashcard-hint';
            var hintIcon = document.createElement('span');
            hintIcon.className = 'flashcard-hint-icon';
            hintIcon.textContent = '\u21BB';
            var hintText = document.createElement('span');
            hintText.textContent = 'Click to flip';
            hint.appendChild(hintIcon);
            hint.appendChild(hintText);
            card.appendChild(hint);
        }

        dom.appendChild(card);

        // --- Event handlers ---

        // Edit toggle
        editBtn.addEventListener('mousedown', function(e) { e.stopPropagation(); e.preventDefault(); });
        editBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            if (editMode) {
                // Leaving edit mode — commit changes
                commitEdits();
            }
            editMode = !editMode;
            flipped = false;
            render();
        });

        if (editMode) {
            // In edit mode: prevent flip, allow text editing
            frontContent.addEventListener('mousedown', function(e) { e.stopPropagation(); });
            backContent.addEventListener('mousedown', function(e) { e.stopPropagation(); });
            setBadge.addEventListener('mousedown', function(e) { e.stopPropagation(); });
            frontContent.addEventListener('click', function(e) { e.stopPropagation(); });
            backContent.addEventListener('click', function(e) { e.stopPropagation(); });
            setBadge.addEventListener('click', function(e) { e.stopPropagation(); });

            // Cmd+Z: blur first so ProseMirror can handle undo
            function handleKeydown(e) {
                if (e.key === 'Enter') { e.preventDefault(); e.target.blur(); }
                if (e.key === 'Escape') { e.preventDefault(); e.target.blur(); view.focus(); }
                if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
                    e.preventDefault();
                    commitEdits();
                    editMode = false;
                    render();
                    view.focus();
                    // Let ProseMirror handle undo
                    setTimeout(function() {
                        window.executeCommand(e.shiftKey ? 'redo' : 'undo');
                    }, 0);
                }
            }
            frontContent.addEventListener('keydown', handleKeydown);
            backContent.addEventListener('keydown', handleKeydown);
            setBadge.addEventListener('keydown', function(e) {
                if (e.key === 'Enter') { e.preventDefault(); setBadge.blur(); }
                if (e.key === 'Escape') { e.preventDefault(); setBadge.blur(); view.focus(); }
            });

            // Commit on blur
            frontContent.addEventListener('blur', commitEdits);
            backContent.addEventListener('blur', commitEdits);
            setBadge.addEventListener('blur', commitEdits);

            // Flip by clicking the card body (not content areas) even in edit mode
            card.addEventListener('click', function(e) {
                if (e.target.closest('.flashcard-content') || e.target.closest('.flashcard-set-badge')) return;
                flipped = !flipped;
                card.setAttribute('data-flipped', flipped ? 'true' : 'false');
            });
        } else {
            // Study mode: click anywhere on card flips
            card.addEventListener('click', function() {
                flipped = !flipped;
                card.setAttribute('data-flipped', flipped ? 'true' : 'false');
            });
        }

        function commitEdits() {
            if (typeof getPos !== 'function') return;
            var newQ = frontContent.textContent || 'Question';
            var newA = backContent.textContent || 'Answer';
            var newSet = setBadge.textContent.trim();
            if (newQ !== currentQuestion || newA !== currentAnswer || newSet !== currentSet) {
                currentQuestion = newQ;
                currentAnswer = newA;
                currentSet = newSet;
                globalMuteUntil = Date.now() + 500;
                var pos = getPos();
                view.dispatch(view.state.tr.setNodeMarkup(pos, null, {
                    question: currentQuestion,
                    answer: currentAnswer,
                    set: currentSet
                }));
            }
        }
    }

    render();

    return {
        dom: dom,
        update: function(updatedNode) {
            if (updatedNode.type.name !== 'flashcard') return false;
            node = updatedNode;
            var active = document.activeElement;
            var isEditing = editMode && (
                (frontContent && active === frontContent) ||
                (backContent && active === backContent) ||
                (setInput && active === setInput));
            if (!isEditing) {
                currentQuestion = node.attrs.question;
                currentAnswer = node.attrs.answer;
                currentSet = node.attrs.set || '';
                render();
            }
            return true;
        },
        selectNode: function() {},
        deselectNode: function() {},
        stopEvent: function(e) {
            // In edit mode, let the contenteditable handle input events
            if (editMode && e.target && e.target.closest) {
                if (e.target.closest('.flashcard-content') || e.target.closest('.flashcard-set-badge')) return true;
            }
            return false;
        },
        ignoreMutation: function() { return true; },
        destroy: function() {}
    };
}

// ─── Suppress content change during loadContent ───────
var isLoadingContent = false;
// ─── Prevent re-entrant command execution ─────────────
var isExecutingCommand = false;

// ─── Table context menu ───────────────────────────────
function showTableMenu(x, y, table) {
    var old = document.getElementById('table-context-menu');
    if (old) old.remove();

    var menu = document.createElement('div');
    menu.id = 'table-context-menu';
    menu.className = 'yt-context-menu'; // reuse YouTube menu styling
    menu.style.left = x + 'px';
    menu.style.top = y + 'px';

    function addItem(label, action) {
        var item = document.createElement('div');
        item.className = 'yt-menu-item';
        item.textContent = label;
        item.addEventListener('mousedown', function(e) {
            e.preventDefault();
            action();
            menu.remove();
        });
        menu.appendChild(item);
    }

    function addToggle(label, attr) {
        var current = table.getAttribute(attr) === 'true';
        var item = document.createElement('div');
        item.className = 'yt-menu-item';
        item.textContent = (current ? '\u2713 ' : '   ') + label;
        item.addEventListener('mousedown', function(e) {
            e.preventDefault();
            table.setAttribute(attr, current ? 'false' : 'true');
            menu.remove();
        });
        menu.appendChild(item);
    }

    function addSep() {
        var sep = document.createElement('div');
        sep.className = 'yt-menu-sep';
        menu.appendChild(sep);
    }

    // Style toggles
    addToggle('Header background', 'data-header');
    addToggle('Striped rows', 'data-striped');
    addToggle('Column borders', 'data-borders');
    addToggle('Table outline', 'data-outline');
    addSep();

    // Header colors
    var colorLabel = document.createElement('div');
    colorLabel.className = 'yt-menu-item';
    colorLabel.style.cssText = 'font-size:11px;color:var(--text-secondary);cursor:default;';
    colorLabel.textContent = 'Header color:';
    menu.appendChild(colorLabel);

    var colorRow = document.createElement('div');
    colorRow.style.cssText = 'display:flex;gap:4px;padding:4px 12px;';
    var colorDefs = [
        { name: '', hex: '#6E7681' },
        { name: 'blue', hex: '#4A90D9' },
        { name: 'green', hex: '#34C759' },
        { name: 'purple', hex: '#AF52DE' },
        { name: 'orange', hex: '#FF9500' }
    ];
    colorDefs.forEach(function(c) {
        var dot = document.createElement('button');
        dot.style.cssText = 'width:16px;height:16px;border-radius:50%;border:2px solid transparent;background:' + c.hex + ';cursor:pointer;padding:0;';
        if (table.getAttribute('data-color') === c.name) dot.style.borderColor = 'var(--text)';
        dot.addEventListener('mousedown', function(e) {
            e.preventDefault();
            if (c.name) table.setAttribute('data-color', c.name);
            else table.removeAttribute('data-color');
            menu.remove();
        });
        colorRow.appendChild(dot);
    });
    menu.appendChild(colorRow);
    addSep();

    // Structure actions
    addItem('Add row above', function() {
        globalMuteUntil = Date.now() + 500;
        isExecutingCommand = true;
        setTimeout(function() {
            try { editorInstance.ctx.get(commandsCtx).call(addRowBeforeCommand.key); } catch(e) {}
            isExecutingCommand = false;
        }, 0);
    });
    addItem('Add row below', function() {
        globalMuteUntil = Date.now() + 500;
        isExecutingCommand = true;
        setTimeout(function() {
            try { editorInstance.ctx.get(commandsCtx).call(addRowAfterCommand.key); } catch(e) {}
            isExecutingCommand = false;
        }, 0);
    });
    addItem('Add column left', function() {
        globalMuteUntil = Date.now() + 500;
        isExecutingCommand = true;
        setTimeout(function() {
            try { editorInstance.ctx.get(commandsCtx).call(addColBeforeCommand.key); } catch(e) {}
            isExecutingCommand = false;
        }, 0);
    });
    addItem('Add column right', function() {
        globalMuteUntil = Date.now() + 500;
        isExecutingCommand = true;
        setTimeout(function() {
            try { editorInstance.ctx.get(commandsCtx).call(addColAfterCommand.key); } catch(e) {}
            isExecutingCommand = false;
        }, 0);
    });
    addSep();

    // Danger actions
    var delRow = document.createElement('div');
    delRow.className = 'yt-menu-item';
    delRow.textContent = 'Delete row';
    delRow.style.color = '#FF3B30';
    delRow.addEventListener('mousedown', function(e) {
        e.preventDefault();
        globalMuteUntil = Date.now() + 500;
        try {
            var view = editorInstance.ctx.get(editorViewCtx);
            deleteRow(view.state, view.dispatch);
        } catch(ex) {}
        menu.remove();
    });
    menu.appendChild(delRow);

    var delCol = document.createElement('div');
    delCol.className = 'yt-menu-item';
    delCol.textContent = 'Delete column';
    delCol.style.color = '#FF3B30';
    delCol.addEventListener('mousedown', function(e) {
        e.preventDefault();
        globalMuteUntil = Date.now() + 500;
        try {
            var view = editorInstance.ctx.get(editorViewCtx);
            deleteColumn(view.state, view.dispatch);
        } catch(ex) {}
        menu.remove();
    });
    menu.appendChild(delCol);

    var delTable = document.createElement('div');
    delTable.className = 'yt-menu-item';
    delTable.textContent = 'Delete table';
    delTable.style.color = '#FF3B30';
    delTable.addEventListener('mousedown', function(e) {
        e.preventDefault();
        globalMuteUntil = Date.now() + 500;
        try {
            var view = editorInstance.ctx.get(editorViewCtx);
            deleteTable(view.state, view.dispatch);
        } catch(ex) {}
        menu.remove();
    });
    menu.appendChild(delTable);

    document.body.appendChild(menu);
    setTimeout(function() {
        document.addEventListener('mousedown', function close(e) {
            if (!menu.contains(e.target)) { menu.remove(); document.removeEventListener('mousedown', close); }
        });
    }, 10);
}

// ─── Main init ─────────────────────────────────────────
var editorInstance = null;

async function initEditor() {
    var editor = await Editor.make()
        .config(function(ctx) {
            ctx.set(rootCtx, '#editor');
            ctx.set(defaultValueCtx, '');

            var lm = ctx.get(listenerCtx);
            lm.markdownUpdated(function(ctx, markdown, prevMarkdown) {
                if (!isLoadingContent && !isExecutingCommand && markdown !== prevMarkdown) {
                    scheduleContentChange(editor);
                }
            });
        })
        .use(commonmark)
        .use(gfmFiltered)
        .use(math)
        // mathAutoDetectPlugin removed — was causing cursor/selection issues
        // mathTrailingStrutPlugin removed — was breaking text selection
        .use(history)
        .use(listener)
        .use(unifiedPastePlugin)
        .use(clipboard)
        .use(trailing)
        .use(indent)
        .use(stateChangePlugin)
        .use(customKeymapPlugin)
        // formatBarPlugin removed — handled by SwiftUI toolbar
        .use(slashMenuPluginFixed)
        .use(findBarPlugin)
        // tableToolbarPlugin deferred — added 2s after init to avoid WebKit render flood
        .use(checkboxPlugin)
        .use(mathNodeViewPlugin)
        // mathPastePlugin removed — merged into unifiedPastePlugin
        .use(youtubeVideoSchema)
        .use(youtubeNodeViewPlugin)
        // youtubeAutoDetectPlugin removed — YouTube URLs detected on paste and load only
        .use(remarkFlashcard)
        .use(flashcardSchema)
        .use(flashcardNodeViewPlugin)
        .create();

    editorInstance = editor;
    setupScrollTracking();

    // Debug: log schema to console so we know exact node/mark names
    try {
        var view = editor.ctx.get(editorViewCtx);
        console.log('[SCHEMA] Nodes:', Object.keys(view.state.schema.nodes).join(', '));
        console.log('[SCHEMA] Marks:', Object.keys(view.state.schema.marks).join(', '));
    } catch(e) {
        console.warn('[SCHEMA] Could not read schema:', e.message);
    }

    // Send ready exactly once
    if (!hasNotifiedReady) {
        hasNotifiedReady = true;
        sendToSwift('ready', {});
    }

    // Table context menu for settings — no continuous polling, only fires on right-click
    setTimeout(function() {
        var editorEl = document.getElementById('editor');
        if (!editorEl) return;
        editorEl.addEventListener('contextmenu', function(e) {
            // Check if right-click is inside a table
            var td = e.target.closest('td, th');
            if (!td) return;
            var table = td.closest('table');
            if (!table) return;

            e.preventDefault();
            e.stopPropagation();
            showTableMenu(e.clientX, e.clientY, table);
        });
    }, 500);
}

// ─── Checkbox toggle from DOM click ───────────────────
window.toggleCheckboxAtElement = function(liElement) {
    if (!editorInstance) return;
    try {
        var view = editorInstance.ctx.get(editorViewCtx);
        var pos = view.posAtDOM(liElement, 0);
        if (pos === undefined || pos === null) return;
        var $pos = view.state.doc.resolve(pos);
        for (var d = $pos.depth; d >= 0; d--) {
            var node = $pos.node(d);
            if (node.type.name === 'list_item' && node.attrs.checked !== null && node.attrs.checked !== undefined) {
                var nodePos = $pos.before(d);
                var attrs = Object.assign({}, node.attrs);
                attrs.checked = !attrs.checked;
                var tr = view.state.tr.setNodeMarkup(nodePos, null, attrs);
                view.dispatch(tr);
                return;
            }
        }
    } catch(e) {
        console.warn('[Prism] toggleCheckbox error:', e.message);
    }
};

// ─── Bridge: Swift → JS ───────────────────────────────

window.loadContent = function(markdown) {
    if (!editorInstance) return;

    isLoadingContent = true;
    clearTimeout(contentChangeTimer);

    try {
        editorInstance.action(function(ctx) {
            var view = ctx.get(editorViewCtx);
            var parser = ctx.get(parserCtx);
            var doc = parser(markdown || '');

            if (doc) {
                var tr = view.state.tr;
                tr.replaceWith(0, view.state.doc.content.size, doc.content);
                tr.setMeta('addToHistory', false);
                view.dispatch(tr);
            }
        });
    } catch(e) {
        console.error('[Prism] loadContent error:', e);
    }

    // Re-enable content change tracking — generous window to prevent feedback loops
    setTimeout(function() {
        isLoadingContent = false;
        // Post-load: scan for YouTube URLs and image-links, convert to embeds
        setTimeout(function() {
            if (!editorInstance) return;
            try {
                var view = editorInstance.ctx.get(editorViewCtx);
                var ytType = view.state.schema.nodes.youtube_video;
                if (!ytType) return;
                var tr = view.state.tr;
                var modified = false;
                var replacements = [];

                view.state.doc.descendants(function(node, pos) {
                    // Check paragraphs containing bare YouTube URLs
                    if (node.type.name === 'paragraph' && node.content.size > 0) {
                        var text = node.textContent.trim();
                        var vid = extractYouTubeId(text);
                        if (vid && text.match(/^(https?:\/\/)?(www\.)?(youtube\.com|youtu\.be)\//)) {
                            replacements.push({ pos: pos, size: node.nodeSize, vid: vid });
                            return false;
                        }
                    }
                    // Check images with YouTube thumbnail src or links to YouTube
                    if (node.type.name === 'image') {
                        var src = node.attrs.src || '';
                        var vid2 = null;
                        if (src.indexOf('img.youtube.com') >= 0) {
                            var m = src.match(/\/vi\/([a-zA-Z0-9_-]{11})\//);
                            if (m) vid2 = m[1];
                        }
                        if (vid2) {
                            // Find the parent paragraph to replace
                            replacements.push({ pos: pos, size: node.nodeSize, vid: vid2 });
                            return false;
                        }
                    }
                    // Check links pointing to YouTube
                    if (node.type.name === 'paragraph') {
                        node.content.forEach(function(child) {
                            if (child.type.name === 'image' || (child.marks && child.marks.length > 0)) {
                                var marks = child.marks || [];
                                for (var i = 0; i < marks.length; i++) {
                                    if (marks[i].type.name === 'link') {
                                        var href = marks[i].attrs.href || '';
                                        var vid3 = extractYouTubeId(href);
                                        if (vid3) {
                                            replacements.push({ pos: pos, size: node.nodeSize, vid: vid3 });
                                            return;
                                        }
                                    }
                                }
                            }
                        });
                    }
                });

                // Apply replacements in reverse order
                replacements.sort(function(a, b) { return b.pos - a.pos; });
                for (var i = 0; i < replacements.length; i++) {
                    var r = replacements[i];
                    try {
                        tr.replaceWith(r.pos, r.pos + r.size, ytType.create({ videoId: r.vid }));
                        modified = true;
                        sendToSwift('fetchVideoMeta', { videoId: r.vid });
                    } catch(e) {}
                }

                if (modified) {
                    globalMuteUntil = Date.now() + 1000;
                    view.dispatch(tr);
                }
            } catch(e) {}
        }, 300);
    }, 200);
};

window.getContent = function() {
    if (!editorInstance) return '';
    try {
        var ctx = editorInstance.ctx;
        var serializer = ctx.get(serializerCtx);
        var view = ctx.get(editorViewCtx);
        return serializer(view.state.doc);
    } catch(e) {
        console.error('[Prism] getContent error:', e);
        return '';
    }
};

window.executeCommand = function(command, payload) {
    if (!editorInstance) { console.warn('[CMD] No editor'); return; }
    if (isExecutingCommand) { console.warn('[CMD] Re-entrant, skipping:', command); return; }

    // Mute ALL bridge messages for 500ms to prevent feedback loops
    globalMuteUntil = Date.now() + 500;

    console.log('[CMD] ' + command, payload ? JSON.stringify(payload) : '');

    // Use setTimeout to break out of any current ProseMirror transaction cycle
    setTimeout(function() {
        isExecutingCommand = true;
        try {
            var commands;
            try {
                commands = editorInstance.ctx.get(commandsCtx);
            } catch(e) {
                console.error('[CMD] Cannot get commands context:', e.message);
                return;
            }

            var view;
            try {
                view = editorInstance.ctx.get(editorViewCtx);
            } catch(e) {
                console.error('[CMD] Cannot get editor view:', e.message);
                return;
            }

            // Focus the editor first so commands have a valid selection
            view.focus();

            switch(command) {
                case 'bold':
                    commands.call(toggleStrongCommand.key);
                    break;
                case 'italic':
                    commands.call(toggleEmphasisCommand.key);
                    break;
                case 'inlineCode':
                    commands.call(toggleInlineCodeCommand.key);
                    break;
                case 'strikethrough':
                    commands.call(toggleStrikethroughCommand.key);
                    break;
                case 'link':
                    sendToSwift('requestLink', {});
                    break;
                case 'heading':
                    if (payload && payload.level) {
                        commands.call(wrapInHeadingCommand.key, payload.level);
                    }
                    break;
                case 'paragraph':
                    commands.call(turnIntoTextCommand.key);
                    break;
                case 'bulletList':
                    commands.call(wrapInBulletListCommand.key);
                    break;
                case 'orderedList':
                    commands.call(wrapInOrderedListCommand.key);
                    break;
                case 'taskList': {
                    // GFM task lists: create a bullet list, then toggle the checked attribute
                    // First ensure we're in a bullet list
                    var state = view.state;
                    var listItemType = state.schema.nodes.list_item;
                    if (listItemType) {
                        // Wrap in bullet list first if not already in one
                        commands.call(wrapInBulletListCommand.key);
                        // Then set the checked attribute on the list item
                        var newState = view.state;
                        var $pos = newState.selection.$from;
                        for (var d = $pos.depth; d > 0; d--) {
                            var node = $pos.node(d);
                            if (node.type.name === 'list_item') {
                                var pos = $pos.before(d);
                                var attrs = Object.assign({}, node.attrs);
                                // Toggle: if already checked (true/false), remove it; otherwise set to false
                                if (attrs.checked !== null && attrs.checked !== undefined) {
                                    attrs.checked = null;
                                } else {
                                    attrs.checked = false;
                                }
                                var tr = newState.tr.setNodeMarkup(pos, null, attrs);
                                view.dispatch(tr);
                                break;
                            }
                        }
                    }
                    break;
                }
                case 'blockquote':
                    commands.call(wrapInBlockquoteCommand.key);
                    break;
                case 'codeBlock': {
                    // Deferred insertion via markdown reload to avoid WebKit rendering flood
                    var serializer = editorInstance.ctx.get(serializerCtx);
                    var md = serializer(view.state.doc);
                    var codeMd = '\n\n```\ncode\n```\n';
                    requestAnimationFrame(function() {
                        requestAnimationFrame(function() {
                            window.loadContent(md + codeMd);
                        });
                    });
                    break;
                }
                case 'horizontalRule':
                    commands.call(insertHrCommand.key);
                    break;
                case 'insertTable': {
                    // Deferred insertion via markdown reload to avoid WebKit rendering flood
                    var serializer2 = editorInstance.ctx.get(serializerCtx);
                    var md2 = serializer2(view.state.doc);
                    var tableMd = '\n\n| Header 1 | Header 2 | Header 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n';
                    requestAnimationFrame(function() {
                        requestAnimationFrame(function() {
                            window.loadContent(md2 + tableMd);
                        });
                    });
                    break;
                }
                case 'insertMathBlock':
                case 'mathBlock': {
                    // Insert block math delimiter
                    view.focus();
                    document.execCommand('insertText', false, '\n$$\n\n$$\n');
                    break;
                }
                case 'mathInline': {
                    // Insert inline math delimiter
                    view.focus();
                    document.execCommand('insertText', false, '$E = mc^2$');
                    break;
                }
                case 'chemistry': {
                    view.focus();
                    document.execCommand('insertText', false, '$\\ce{H2O}$');
                    break;
                }
                case 'insertYouTube': {
                    var ytUrl = prompt('Enter YouTube URL:');
                    if (ytUrl) {
                        var ytId = extractYouTubeId(ytUrl.trim());
                        if (ytId) {
                            var ytType = view.state.schema.nodes.youtube_video;
                            if (ytType) {
                                var ytNode = ytType.create({ videoId: ytId });
                                view.dispatch(view.state.tr.replaceSelectionWith(ytNode));
                                sendToSwift('fetchVideoMeta', { videoId: ytId });
                            }
                        }
                    }
                    break;
                }
                case 'insertFlashcard': {
                    var fcType = view.state.schema.nodes.flashcard;
                    if (fcType) {
                        var fcNode = fcType.create({ question: 'Question', answer: 'Answer' });
                        view.dispatch(view.state.tr.replaceSelectionWith(fcNode));
                    }
                    break;
                }
                case 'undo':
                    commands.call(undoCommand.key);
                    break;
                case 'redo':
                    commands.call(redoCommand.key);
                    break;
                case 'indent':
                    commands.call(sinkListItemCommand.key);
                    break;
                case 'outdent':
                    commands.call(liftListItemCommand.key);
                    break;
                case 'find':
                    if (typeof window.showFindBar === 'function') window.showFindBar(false);
                    break;
                case 'findReplace':
                    if (typeof window.showFindBar === 'function') window.showFindBar(true);
                    break;
                case 'save':
                    sendToSwift('save', {});
                    break;
                case 'selectAll': {
                    var tr = view.state.tr.setSelection(new AllSelection(view.state.doc));
                    view.dispatch(tr);
                    break;
                }
                default:
                    console.warn('[CMD] Unknown:', command);
            }
            console.log('[CMD] OK:', command);
        } catch(e) {
            console.error('[CMD ERROR] ' + command + ': ' + e.message, e.stack);
        } finally {
            isExecutingCommand = false;
        }
    }, 0);
};

window.setTheme = function(theme) {
    document.documentElement.setAttribute('data-theme', theme);
};

window.setEditable = function(editable) {
    if (!editorInstance) return;
    try {
        var view = editorInstance.ctx.get(editorViewCtx);
        view.setProps({ editable: function() { return editable; } });
        document.body.classList.toggle('reading-mode', !editable);
    } catch(e) {
        console.error('[Prism] setEditable error:', e);
    }
};

window.insertLinkWithURL = function(url) {
    if (!editorInstance) return;
    try {
        var commands = editorInstance.ctx.get(commandsCtx);
        commands.call(toggleLinkCommand.key, { href: url });
    } catch(e) {
        console.error('[Prism] insertLinkWithURL error:', e);
    }
};

window.getScrollPosition = function() {
    return window.scrollY;
};

window.setScrollPosition = function(y) {
    window.scrollTo(0, y);
};

window.getCursorPosition = function() {
    if (!editorInstance) return 0;
    try {
        var view = editorInstance.ctx.get(editorViewCtx);
        return view.state.selection.from;
    } catch(e) {
        return 0;
    }
};

window.setCursorPosition = function(offset) {
    if (!editorInstance) return;
    try {
        var view = editorInstance.ctx.get(editorViewCtx);
        var doc = view.state.doc;
        var pos = Math.min(offset, doc.content.size);
        var selection = TextSelection.near(doc.resolve(pos));
        var tr = view.state.tr.setSelection(selection);
        view.dispatch(tr);
        view.focus();
    } catch(e) {
        console.error('[Prism] setCursorPosition error:', e);
    }
};

// ─── Focus helper ──────────────────────────────────────
window.focusEditor = function() {
    if (!editorInstance) return;
    try {
        var view = editorInstance.ctx.get(editorViewCtx);
        view.focus();
    } catch(e) {
        // ignore
    }
};

// ─── Bootstrap ─────────────────────────────────────────
initEditor();
