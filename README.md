# git-report

## Build status
[![CircleCI](https://circleci.com/gh/mfiscus/git-report.svg?style=svg)](https://circleci.com/gh/mfiscus/git-report)

## Prerequisites

1. Go to https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line
*   Generate a personal access token
*   Create a file named git-report.token and put your key in it
      ```bash
      echo "<your key here>" > ~/Projects/git-report/git-report.token
      ```

## Installation

1. Check out a clone of this repo to your local Projects directory
   ```bash
   cd ~/Projects && git clone https://github.com/mfiscus/git-report.git && cd git-report
   ```
2. Make script executable
   ```bash
   chmod +x git-report.sh
   ```

3. Run `./git-report.sh --help`
