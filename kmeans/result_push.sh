#!/bin/bash
make clean &&\
make kmeans_parallel_sorting_stream &&\
ncu_execute kmeans_parallel_sorting_stream $1&&\
git add -A &&\
git commit -m 'a' &&\
git push