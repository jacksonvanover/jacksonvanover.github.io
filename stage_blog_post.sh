#!/bin/bash

FROM_ABSPATH=$(realpath $(dirname "${1}" | head -n 1))
FROM_FILENAME=$(basename "${1}")

TO_FILENAME=${FROM_FILENAME// /-}
TO_FILENAME=$(date +"%Y-%m-%d")-"${TO_FILENAME}"

cp "${1}" docs/_posts/"${TO_FILENAME}"

# add front matter
sed -i '1s/^/---\n/' docs/_posts/"${TO_FILENAME}"
sed -i '1s/^/discussed: \n/' docs/_posts/"${TO_FILENAME}"
sed -i "1s/^/title: ${FROM_FILENAME%.*}\n/" docs/_posts/"${TO_FILENAME}"
sed -i '1s/^/layout: blog\n/' docs/_posts/"${TO_FILENAME}"
sed -i '1s/^/---\n/' docs/_posts/"${TO_FILENAME}"

# change image paths
sed -Ei 's|^!\[\[([^]]+)\]\]|![](/assets/img/\1)|' docs/_posts/"${TO_FILENAME}"

# fix latex equations
sed -i 's|\$|\$\$|g' docs/_posts/"${TO_FILENAME}"
sed -i 's|^\$\$\$\$|<div class="equation">\$\$|g' docs/_posts/"${TO_FILENAME}"
sed -i 's|\$\$\$\$|\$\$</div>|g' docs/_posts/"${TO_FILENAME}"

# copy over images
grep -oe "/assets/img/.*png" docs/_posts/"${TO_FILENAME}" | while read x
do
    IMG_NAME=$(basename "${x}")
    cp "${FROM_ABSPATH}/${IMG_NAME}" "docs/assets/img/${IMG_NAME}"
done