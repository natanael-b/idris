#!/usr/bin/bash

which lua5.4 || sudo apt install lua5.4 > /dev/null 2>&1

input='crie o arquivo teste.txt, coloque nele a frase Olá Mundo!, abra no kate e mova ele para /tmp'

hash="16a282a5576a2cd962eea033ce4da66346a288380ee53a548862ae96469b50bc"

hash_input=$(lua5.4 idris.lua --lang=pt_BR --database=demonstration "${input}" | sha256sum | cut -d' ' -f1)

[ "${hash}" = "${hash_input}" ] && {
  exit 0
}

echo "Error: The '${input}' has generated a different output"
exit 1
