// editor.js — Post-bundle DOM enhancements
(function() {
    'use strict';

    // ─── Placeholder observer ────────────────────────────
    function setupPlaceholder() {
        var editorEl = document.getElementById('editor');
        if (!editorEl) return;

        var observer = new MutationObserver(function() {
            var pm = editorEl.querySelector('.ProseMirror');
            if (!pm) return;

            var text = pm.textContent.trim();
            var childCount = pm.children.length;
            var firstChild = pm.firstElementChild;

            var hasOnlyEmptyParagraph = (
                childCount === 1 &&
                firstChild &&
                firstChild.tagName === 'P' &&
                firstChild.textContent.trim() === ''
            );

            var isEmpty = text === '' || hasOnlyEmptyParagraph;

            if (isEmpty) {
                pm.classList.add('is-empty');
                if (firstChild) firstChild.classList.add('is-editor-empty');
            } else {
                pm.classList.remove('is-empty');
                var emptyP = pm.querySelector('.is-editor-empty');
                if (emptyP) emptyP.classList.remove('is-editor-empty');
            }
        });

        observer.observe(editorEl, {
            childList: true,
            subtree: true,
            characterData: true
        });
    }

    // ─── Code block language label + copy button ─────────
    function setupCodeBlockEnhancements() {
        var editorEl = document.getElementById('editor');
        if (!editorEl) return;

        var observer = new MutationObserver(function() {
            var preElements = editorEl.querySelectorAll('.ProseMirror pre');
            for (var i = 0; i < preElements.length; i++) {
                var pre = preElements[i];
                // Skip if already wrapped
                if (pre.parentElement && pre.parentElement.classList.contains('code-block-wrapper')) {
                    // Update language label if it changed
                    updateLanguageLabel(pre);
                    continue;
                }
                wrapCodeBlock(pre);
            }
        });

        observer.observe(editorEl, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['data-language']
        });

        // Initial pass
        setTimeout(function() {
            var preElements = editorEl.querySelectorAll('.ProseMirror pre');
            for (var i = 0; i < preElements.length; i++) {
                if (!preElements[i].parentElement || !preElements[i].parentElement.classList.contains('code-block-wrapper')) {
                    wrapCodeBlock(preElements[i]);
                }
            }
        }, 200);
    }

    function getLanguage(pre) {
        // Milkdown sets data-language on the pre or its parent
        var lang = pre.getAttribute('data-language');
        if (!lang) {
            var code = pre.querySelector('code');
            if (code) {
                lang = code.getAttribute('data-language');
                if (!lang) {
                    // Check class like "language-javascript"
                    var cls = code.className || '';
                    var match = cls.match(/language-(\S+)/);
                    if (match) lang = match[1];
                }
            }
        }
        return lang || '';
    }

    function updateLanguageLabel(pre) {
        var wrapper = pre.parentElement;
        if (!wrapper || !wrapper.classList.contains('code-block-wrapper')) return;
        var labelEl = wrapper.querySelector('.code-block-lang');
        if (!labelEl) return;
        var lang = getLanguage(pre);
        if (labelEl.textContent !== lang) {
            labelEl.textContent = lang;
        }
    }

    function wrapCodeBlock(pre) {
        var lang = getLanguage(pre);

        var wrapper = document.createElement('div');
        wrapper.className = 'code-block-wrapper';
        wrapper.setAttribute('contenteditable', 'false');

        var header = document.createElement('div');
        header.className = 'code-block-header';

        var langLabel = document.createElement('span');
        langLabel.className = 'code-block-lang';
        langLabel.textContent = lang;

        var copyBtn = document.createElement('button');
        copyBtn.className = 'code-block-copy';
        copyBtn.textContent = 'Copy';
        copyBtn.setAttribute('type', 'button');
        copyBtn.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            var code = pre.querySelector('code');
            var text = code ? code.textContent : pre.textContent;
            copyToClipboard(text, copyBtn);
        });

        header.appendChild(langLabel);
        header.appendChild(copyBtn);

        pre.parentNode.insertBefore(wrapper, pre);
        wrapper.appendChild(header);
        wrapper.appendChild(pre);
    }

    function copyToClipboard(text, btn) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function() {
                showCopied(btn);
            }).catch(function() {
                fallbackCopy(text, btn);
            });
        } else {
            fallbackCopy(text, btn);
        }
    }

    function fallbackCopy(text, btn) {
        var textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        try {
            document.execCommand('copy');
            showCopied(btn);
        } catch(e) {
            // silent fail
        }
        document.body.removeChild(textarea);
    }

    function showCopied(btn) {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(function() {
            btn.textContent = 'Copy';
            btn.classList.remove('copied');
        }, 1500);
    }

    // ─── Checkbox click handler ────────────────────────────
    function setupCheckboxClicks() {
        var editorEl = document.getElementById('editor');
        if (!editorEl) return;

        editorEl.addEventListener('click', function(e) {
            // Check if the click is on the left side of a task list item (where the checkbox is)
            var li = e.target.closest('li[data-checked]');
            if (!li) return;

            var rect = li.getBoundingClientRect();
            // Only toggle if clicked in the checkbox area (first ~24px from the left)
            if (e.clientX - rect.left > 28) return;

            // Toggle the attribute
            var isChecked = li.getAttribute('data-checked');
            var newVal = isChecked === 'true' ? 'false' : 'true';
            li.setAttribute('data-checked', newVal);

            // Also update ProseMirror state via the global command
            if (typeof window.toggleCheckboxAtElement === 'function') {
                window.toggleCheckboxAtElement(li);
            }
        });
    }

    // ─── Init ────────────────────────────────────────────
    function init() {
        setTimeout(function() {
            setupPlaceholder();
            setupCodeBlockEnhancements();
            setupCheckboxClicks();
        }, 100);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
