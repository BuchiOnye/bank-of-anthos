#!/bin/bash

# Quick deployment wrapper that uses gcloud from the correct path
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"

# Run the main deployment script with all defaults
./hackathon-deploy.sh -a all