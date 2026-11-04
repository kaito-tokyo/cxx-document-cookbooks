// SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
//
// SPDX-License-Identifier: Apache-2.0

// usage: node check-math.js TOKENS.jsonl
//
// Converts every distinct "math" and "displaymath" token with MathJax's TeX
// input, configured like MathJax's default (the base and ams packages, no
// textmacros), prints the ones that fail, and exits with status 1 if any
// does. Needs MathJax 3 (Ubuntu: node-mathjax-full).
'use strict';
const fs = require('fs');
const {mathjax} = require('mathjax-full/js/mathjax.js');
const {TeX} = require('mathjax-full/js/input/tex.js');
const {liteAdaptor} = require('mathjax-full/js/adaptors/liteAdaptor.js');
const {RegisterHTMLHandler} = require('mathjax-full/js/handlers/html.js');
const {STATE} = require('mathjax-full/js/core/MathItem.js');
const {SerializedMmlVisitor} = require('mathjax-full/js/core/MmlTree/SerializedMmlVisitor.js');
require('mathjax-full/js/input/tex/base/BaseConfiguration.js');
require('mathjax-full/js/input/tex/ams/AmsConfiguration.js');

const formulas = new Map(); // TeX -> {display, count}
for (const line of fs.readFileSync(process.argv[2], 'utf8').split('\n')) {
  if (!line) continue;
  const token = JSON.parse(line);
  for (const kind of ['math', 'displaymath']) {
    if (kind in token) {
      const f = formulas.get(token[kind]) || {display: kind === 'displaymath', count: 0};
      f.count++;
      formulas.set(token[kind], f);
    }
  }
}

RegisterHTMLHandler(liteAdaptor());
const tex = new TeX({packages: ['base', 'ams'], formatError: (jax, err) => { throw err; }});
const doc = mathjax.document('', {InputJax: tex});
const visitor = new SerializedMmlVisitor();
let failed = 0;
for (const [source, f] of formulas) {
  try {
    const mml = visitor.visitTree(doc.convert(source, {display: f.display, end: STATE.CONVERT}));
    if (mml.includes('<merror')) throw new Error('merror in output');
  } catch (e) {
    failed++;
    console.log(`${e.message} (${f.count}x): ${source}`);
  }
}
console.log(`${formulas.size - failed} of ${formulas.size} distinct formulas convert`);
process.exit(failed ? 1 : 0);
