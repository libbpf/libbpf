#!/bin/bash

printf "all:\n\ttouch bpf_testmod.ko\n\nclean:\n" > bpf_testmod/Makefile
printf "all:\n\ttouch bpf_test_no_cfi.ko\n\nclean:\n" > bpf_test_no_cfi/Makefile

