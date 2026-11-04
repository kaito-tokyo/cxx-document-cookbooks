// SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
//
// SPDX-License-Identifier: Apache-2.0

// Reads [{"tex": ..., "display": bool}, ...] as JSON on stdin and writes
// {"css": ..., "html": [...]} to stdout: each formula typeset by MathJax 3
// (TeX input with the base and ams packages, SVG output with its glyphs
// in the SVG itself) and the style sheet the SVGs need. Needs MathJax 3 for
// Node (Ubuntu: node-mathjax-full).
'use strict';
const fs = require('fs');
const {mathjax} = require('mathjax-full/js/mathjax.js');
const {TeX} = require('mathjax-full/js/input/tex.js');
const {SVG} = require('mathjax-full/js/output/svg.js');
const {liteAdaptor} = require('mathjax-full/js/adaptors/liteAdaptor.js');
const {RegisterHTMLHandler} = require('mathjax-full/js/handlers/html.js');
require('mathjax-full/js/input/tex/base/BaseConfiguration.js');
require('mathjax-full/js/input/tex/ams/AmsConfiguration.js');

const formulas = JSON.parse(fs.readFileSync(0, 'utf8'));
const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const doc = mathjax.document('', {
  InputJax: new TeX({packages: ['base', 'ams']}),
  OutputJax: new SVG({fontCache: 'local'}),
});
const html = formulas.map(f => adaptor.outerHTML(doc.convert(f.tex, {display: f.display})));
const css = adaptor.textContent(doc.outputJax.styleSheet(doc));
process.stdout.write(JSON.stringify({css, html}));
