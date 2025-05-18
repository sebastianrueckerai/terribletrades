#!/bin/bash
ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519_trading_app root@91.99.85.74 kubectl $@
