#!/usr/bin/env bash

cpuarch() {
    case $(uname -m) in
        x86_64|amd64 )
            echo amd64
            ;;
        armv6l|armv6 )
            echo armv6
            ;;
        armv7l|armv7 )
            echo armv7
            ;;
        arm64|aarch64)
            echo arm64
            ;;
    esac
}

function _curl() {
  curl --silent --location "$@"
}

install_cfssl () {
  if [ -z "$(command -v cfssl)" ]
  then
      if [ ! -x ./cfssl ]
      then
          echo 'cfssl not found: downloading to current directory...'
          OSTYPE=$(uname -s | awk '{print tolower($0)}')
          CPUARCH=$(cpuarch)
          if [[ "$OSTYPE" == 'darwin'* && "$CPUARCH" == 'arm'* ]]; then
            CPUARCH="amd64"
          fi

          VERSION=$(_curl "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
          VNUMBER=${VERSION#"v"}
          url="https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssl_${VNUMBER}_${OSTYPE}_${CPUARCH}"
          _curl "$url" -o cfssl
          chmod +x cfssl
      fi
      _cfssl=./cfssl
  else
      echo "cfssl found"
      _cfssl=cfssl
  fi
}

install_cfssljson () {
  if [ -z "$(command -v cfssljson)" ]
  then
      if [ ! -x ./cfssljson ]
      then
          echo 'cfssljson not found: downloading to current directory...'
          OSTYPE=$(uname -s | awk '{print tolower($0)}')
          CPUARCH=$(cpuarch)
          if [[ "$OSTYPE" == 'darwin'* && "$CPUARCH" == 'arm'* ]]; then
            CPUARCH="amd64"
          fi
          VERSION=$(_curl "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
          VNUMBER=${VERSION#"v"}
          url="https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssljson_${VNUMBER}_${OSTYPE}_${CPUARCH}"
          _curl "$url" -o cfssljson
          chmod +x cfssljson
      fi
      _cfssljson=./cfssljson
  else
      echo "cfssljson found"
      _cfssljson=cfssljson
  fi
}

install_envsubst () {
  if [ -z "$(command -v envsubst)" ]
  then
      if [ ! -x ./envsubst ]
      then
          echo 'envsubst not found: downloading to current directory...'
          url="https://github.com/a8m/envsubst/releases/download/v1.2.0/envsubst-$(uname -s)-$(uname -m)"
          _curl "$url" -o envsubst
          chmod +x envsubst
      fi
      _envsubst=./envsubst
  else
      echo "envsubst found"
      _envsubst=envsubst
  fi
}
