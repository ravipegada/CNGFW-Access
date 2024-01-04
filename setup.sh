if command -v jq &> /dev/null; then
  echo "jq exists. No need of setup"
else
  echo "jq doesnt exist. Trying to install it."
  if [[ $(uname -s) == "Darwin" ]]; then
  echo "Detected macOS"

  if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  else
    echo "Homebrew is already installed."
  fi

  echo "Installing jq using Homebrew..."
  brew install jq

elif [[ $(uname -s) == "Linux" ]]; then
  echo "Detected Linux"

  if command -v apt-get &> /dev/null; then
    echo "Installing jq using apt-get..."
    sudo apt-get update
    sudo apt-get install -y jq
  else
    echo "Unsupported Linux distribution. Please install jq manually."
    exit 1
  fi

else
  echo "Unsupported operating system."
  exit 1
fi
fi
