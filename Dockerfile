# Builds TexLive and ChkTex on top of a dev container image.
# Also install common packages, like latexmk and latexindex.
#
# References:
#   - https://github.com/jmuchovej/devcontainers/blob/main/images/src/latex/Dockerfile
#   - https://www.tug.org/texlive/quickinstall.html
#   - https://github.com/qdm12/latexdevcontainer/blob/master/Dockerfile

###############################################################################

ARG BASE_VERSION=noble

ARG CHKTEX_VERSION=1.7.9

ARG TEXDIR="/usr/local/texlive"
ARG TEXUSERDIR="/texlive-user"

ARG CHKTEX_MIRROR="http://download.savannah.gnu.org/releases/chktex"
ARG TEXLIVE_MIRROR="https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz"

ARG SCHEME="scheme-basic"
ARG DOCFILES=0
ARG SRCFILES=0

###############################################################################

FROM mcr.microsoft.com/devcontainers/base:noble AS chktex-builder
ARG CHKTEX_MIRROR
ARG CHKTEX_VERSION
ENV DEBIAN_FRONTEND="noninteractive"

SHELL [ "/bin/bash", "-c" ]

WORKDIR /tmp/chktex-builder

RUN curl -qfL -o- "${CHKTEX_MIRROR}/chktex-${CHKTEX_VERSION}.tar.gz" \
    | tar xz --strip-components 1

RUN ./configure
RUN make

###############################################################################

FROM mcr.microsoft.com/vscode/devcontainers/base:${BASE_VERSION} AS tl-builder
ARG TEXLIVE_MIRROR
ARG TEXDIR
ARG TEXUSERDIR
ARG SCHEME
ARG DOCFILES
ARG SRCFILES

#! Set environment variables
ENV DEBIAN_FRONTEND="noninteractive"
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US.UTF-8"
ENV TERM="xterm"

#* Running the following _should_ work, in principal, but Docker doesn't currently
#*   support this form of execution.
# ENV PATH ${TEXDIR}/bin/$(arch)-linux:${PATH}
#!   c.f. https://github.com/docker/docker/issues/29110
ENV PATH=${TEXDIR}/bin/aarch64-linux:${TEXDIR}/bin/x86_64-linux:${PATH}

#! Move to /tmp/texlive so we can properly build and configure TeX, then clean-up
WORKDIR /tmp/texlive

#* Contents of `./profile.txt` sourced from https://tug.org/texlive/doc/install-tl.html
#* Using heredocs for `./profile.txt` -- https://stackoverflow.com/a/2954835/2714651
#* The acceptable contents of `./profile.txt` can be found here:
#*   https://tug.org/texlive/doc/install-tl.html#PROFILES
COPY <<EOF /tmp/texlive/profile.txt
selected_scheme ${SCHEME}
instopt_adjustpath 0
tlpdbopt_autobackup 0
tlpdbopt_desktop_integration 0
tlpdbopt_file_assocs 0
tlpdbopt_install_docfiles ${DOCFILES}
tlpdbopt_install_srcfiles ${SRCFILES}
EOF

#! This prevents the `COPY --from=tl-builder ...` directives from failing.
RUN mkdir -p "${TEXDIR}" "${TEXUSERDIR}"

#* The installation process is essentially copy-paste of "tl;dr: Unix(ish)" from:
#*   https://tug.org/texlive/quickinstall.html
ENV TEXLIVE_INSTALL_NO_WELCOME=1
ENV TEXLIVE_INSTALL_NO_CONTEXT_CACHE=1

RUN curl -L -o install-tl-unx.tar.gz ${TEXLIVE_MIRROR}
RUN zcat < install-tl-unx.tar.gz | tar xf -  --strip-components=1

RUN perl ./install-tl \
    --no-interaction \
    --texdir ${TEXDIR} \
    --texuserdir ${TEXUSERDIR} \
    --profile /tmp/texlive/profile.txt

###############################################################################

FROM mcr.microsoft.com/devcontainers/base:${BASE_VERSION} AS output
ENV DEBIAN_FRONTEND="noninteractive"
ARG TEXDIR
ARG TEXUSERDIR
ARG CHKTEX_VERSION

#! Set environment variables
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US.UTF-8"
ENV TERM="xterm"

#* Running the following _should_ work, in principal, but Docker doesn't currently
#*   support this form of execution.
# ENV PATH ${TEXDIR}/bin/$(arch)-linux:${PATH}
#!   c.f. https://github.com/docker/docker/issues/29110
ENV PATH=${TEXDIR}/bin/aarch64-linux:${TEXDIR}/bin/x86_64-linux:${PATH}

SHELL [ "/bin/bash", "-c" ]

COPY --from=chktex-builder /tmp/chktex-builder/chktex /usr/local/bin/chktex
COPY --from=tl-builder "${TEXDIR}" "${TEXDIR}"
COPY --from=tl-builder "${TEXUSERDIR}" "${TEXUSERDIR}"

#! Install base packages that users might need later on
RUN <<EOF
set -e
apt update -y
apt install -y --no-install-recommends \
    fontconfig vim neovim python3-pygments ttf-mscorefonts-installer \
    locales
apt clean autoclean
apt autoremove -y
rm -rf /var/lib/apt/lists/*
locale-gen "${LANG}" && update-locale LANG=${LANG}
EOF

#! Install `latexindent` and `latexmk` dependencies
RUN <<EOF
apt update -y
apt install -y --no-install-recommends cpanminus
cpanm -n -q Log::Log4perl XString Log::Dispatch::File YAML::Tiny File::HomeDir Unicode::GCString
apt autoclean
apt autoremove -y
rm -rf /var/lib/{apt,dpkg,cache,log}/
EOF

#! Update the TexLive package manager and minimal packages
RUN <<EOF
tlmgr update --self --all
tlmgr install latexmk latexindent
tlmgr update --all
texhash
EOF

#! Check that the following commands work and have the right permissions
RUN tlmgr version
RUN latexmk -version
RUN texhash --version
RUN chktex --version

WORKDIR /workspace

###############################################################################
