#!/bin/bash

# This script removes orphan image files in the docs/assets/img/ directory
# that are not referenced in any markdown files in the docs/_posts/ directory.
IMG_DIR="docs/assets/img"
POSTS_DIR="docs/_posts" 
# Find all PNG images in the image directory
find "${IMG_DIR}" -type f -name "Pasted*.png" | while read img_path; do
    img_name=$(basename "${img_path}")
    # Check if the image is referenced in any markdown file in the posts directory
    if ! grep -qr "/assets/img/${img_name}" "${POSTS_DIR}"; then
        echo "Removing orphan image: ${img_name}"
        rm "${img_path}"
    fi
done