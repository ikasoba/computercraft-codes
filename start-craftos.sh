#!/usr/bin/env bash

module_dir="$(dirname "$0")"

if [ -z "$craftos_pc" ]; then
  craftos_pc="cc.craftos_pc.CraftOS-PC-Accelerated"
fi

flatpak run "$craftos_pc" --mount-rw "/computercraft-codes=$module_dir"
