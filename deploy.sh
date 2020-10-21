#!/bin/bash

tag="mayeut/manylinux:${POLICY}_${PLATFORM}"
build_id=$(git show -s --format=%cd-%h --date=short $TRAVIS_COMMIT)

docker login -u $QUAY_USERNAME -p $QUAY_PASSWORD
docker push ${tag}
