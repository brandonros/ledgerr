#!/bin/bash

ssh brandon@asusrogstrix.local "kubectl rollout restart deployment/postgrest -n postgrest && kubectl rollout status deployment/postgrest -n postgrest"