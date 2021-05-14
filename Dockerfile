FROM mcr.microsoft.com/powershell:latest
COPY tests/appveyor.prep.ps1 .
RUN pwsh ./appveyor.prep.ps1