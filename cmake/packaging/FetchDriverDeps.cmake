# Own VDD/mouse payloads are source-pinned and verified, never fetched from upstream.
# nefcon and ViGEmBus remain separately pinned external installation dependencies.

include_guard(GLOBAL)

if(NOT WIN32)
  return()
endif()

option(FETCH_DRIVER_DEPS "Download driver dependencies from GitHub Releases" ON)
option(DRIVER_DEPS_REQUIRED "Treat missing driver dependencies as a fatal error" ON)

# Version pins
# GitHub release asset digests, independently matched against downloaded bytes.
set(NEFCON_VERSION "v1.18.74" CACHE STRING "nefcon version tag")
set(NEFCON_SHA256 "" CACHE STRING "SHA256 of a custom nefcon release archive")
set(_NEFCON_SHA256_V1_18_74 "625abcdea9e84577d094ab65a8542c9977eb50f2371d216961af01cf4901f172")
if(NEFCON_VERSION STREQUAL "v1.18.74")
  set(_NEFCON_EFFECTIVE_SHA256 "${_NEFCON_SHA256_V1_18_74}")
else()
  set(_nefcon_sha256_is_stale FALSE)
  if(DEFINED NEFCON_CUSTOM_SHA256_VERSION AND
      NOT "${NEFCON_CUSTOM_SHA256_VERSION}" STREQUAL "${NEFCON_VERSION}" AND
      "${NEFCON_SHA256}" STREQUAL "${NEFCON_CUSTOM_SHA256_VALUE}")
    set(_nefcon_sha256_is_stale TRUE)
  elseif("${NEFCON_SHA256}" STREQUAL "${_NEFCON_SHA256_V1_18_74}")
    set(_nefcon_sha256_is_stale TRUE)
  endif()
  if(NOT NEFCON_SHA256 OR _nefcon_sha256_is_stale)
    message(FATAL_ERROR
      "NEFCON_SHA256 must be provided for custom NEFCON_VERSION=${NEFCON_VERSION}; cached digests from another version are not reused")
  endif()
  set(_NEFCON_EFFECTIVE_SHA256 "${NEFCON_SHA256}")
  set(NEFCON_CUSTOM_SHA256_VERSION "${NEFCON_VERSION}" CACHE INTERNAL
      "custom nefcon version associated with the cached SHA256" FORCE)
  set(NEFCON_CUSTOM_SHA256_VALUE "${NEFCON_SHA256}" CACHE INTERNAL
      "last accepted custom nefcon SHA256" FORCE)
endif()
set(VIGEMBUS_VERSION "v1.22.0" CACHE STRING "ViGEmBus release tag")
set(VIGEMBUS_ASSET_NAME "ViGEmBus_1.22.0_x64_x86_arm64.exe"
    CACHE STRING "ViGEmBus release asset name")
set(VIGEMBUS_SHA256 "89220a7865076b342892f98865f3499fb7c4cfd673159e89d352c360fd014c6a"
    CACHE STRING "SHA256 of the pinned ViGEmBus installer")

# Repositories
set(_NEFCON_REPO "nefarius/nefcon")

# Output directories
set(DRIVER_DEPS_CACHE "${CMAKE_BINARY_DIR}/_driver_deps" CACHE PATH "Driver dependencies cache")
set(NEFCON_DRIVER_DIR "${DRIVER_DEPS_CACHE}/nefcon" CACHE PATH "" FORCE)
set(VIGEMBUS_DIR "${DRIVER_DEPS_CACHE}/vigembus" CACHE PATH "" FORCE)
set(VIGEMBUS_INSTALLER "${VIGEMBUS_DIR}/${VIGEMBUS_ASSET_NAME}"
    CACHE FILEPATH "Pinned ViGEmBus installer" FORCE)

set(_DRIVER_DOWNLOAD_ATTEMPTS 3)
set(_DRIVER_DOWNLOAD_TIMEOUT_SECONDS 60)
set(_DRIVER_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS 15)

# Vendored signed packages keep builds independent of expiring private CI artifacts.
# Their package.json records independent source/version/signing provenance.
set(VMOUSE_DRIVER_DIR "${CMAKE_SOURCE_DIR}/src_assets/windows/drivers/vmouse" CACHE PATH "" FORCE)
set(VDD_DRIVER_DIR "${CMAKE_SOURCE_DIR}/src_assets/windows/drivers/vdd" CACHE PATH "" FORCE)
foreach(_driver IN ITEMS VDD VirtualMouse)
  if(_driver STREQUAL "VDD")
    set(_directory "${VDD_DRIVER_DIR}")
    set(_available VDD_DRIVER_AVAILABLE)
  else()
    set(_directory "${VMOUSE_DRIVER_DIR}")
    set(_available VMOUSE_DRIVER_AVAILABLE)
  endif()
  # A pwsh/MSYS parent can export an incompatible PSModulePath. Let Windows
  # PowerShell construct its own built-in module paths in this child process.
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env --unset=PSModulePath
    "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_SOURCE_DIR}/src_assets/windows/misc/verify-driver-certificate.ps1"
    -Driver "${_driver}" -Directory "${_directory}" RESULT_VARIABLE _verified)
  if(NOT _verified EQUAL 0)
    message(FATAL_ERROR "Own ${_driver} package integrity/signing verification failed")
  endif()
  set(${_available} TRUE CACHE INTERNAL "" FORCE)
endforeach()

if(NOT FETCH_DRIVER_DEPS)
  message(STATUS "Driver dependency downloads disabled (FETCH_DRIVER_DEPS=OFF)")
  return()
endif()

# ---------------------------------------------------------------------------
# Helper: download and optionally verify a file with bounded retries. Partial
# or mismatched downloads are removed between attempts.
# ---------------------------------------------------------------------------
function(_driver_download_with_retries url output_path expected_sha256)
  get_filename_component(_dir "${output_path}" DIRECTORY)
  file(MAKE_DIRECTORY "${_dir}")

  set(_header_arguments)
  foreach(_header IN LISTS ARGN)
    list(APPEND _header_arguments HTTPHEADER "${_header}")
  endforeach()

  foreach(_attempt RANGE 1 ${_DRIVER_DOWNLOAD_ATTEMPTS})
    file(REMOVE "${output_path}")
    file(DOWNLOAD "${url}" "${output_path}"
      STATUS _status
      TLS_VERIFY ON
      TIMEOUT ${_DRIVER_DOWNLOAD_TIMEOUT_SECONDS}
      INACTIVITY_TIMEOUT ${_DRIVER_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS}
      ${_header_arguments})

    list(GET _status 0 _code)
    if(_code EQUAL 0 AND EXISTS "${output_path}")
      file(SIZE "${output_path}" _size)
      if(_size GREATER 0)
        if(NOT expected_sha256)
          return()
        endif()

        file(SHA256 "${output_path}" _actual_sha256)
        if(_actual_sha256 STREQUAL expected_sha256)
          return()
        endif()
        set(_status 1 "SHA256 mismatch (expected ${expected_sha256}, actual ${_actual_sha256})")
        set(_code 1)
      else()
        set(_status 1 "downloaded file is empty")
        set(_code 1)
      endif()
    endif()

    list(GET _status 1 _message)
    file(REMOVE "${output_path}")
    if(_attempt LESS _DRIVER_DOWNLOAD_ATTEMPTS)
      message(STATUS
        "  Download attempt ${_attempt}/${_DRIVER_DOWNLOAD_ATTEMPTS} failed (${_code}): ${_message}; retrying")
    else()
      message(WARNING
        "  Download failed after ${_DRIVER_DOWNLOAD_ATTEMPTS} attempts (${_code}): ${_message}")
    endif()
  endforeach()
endfunction()

# ---------------------------------------------------------------------------
# Helper: download a public release asset (skip if a verified cache exists)
# ---------------------------------------------------------------------------
function(_driver_download url output_path)
  set(_expected_sha256 "")
  if(ARGC GREATER 2)
    set(_expected_sha256 "${ARGV2}")
  endif()

  if(EXISTS "${output_path}")
    if(_expected_sha256)
      file(SHA256 "${output_path}" _cached_sha256)
      if(_cached_sha256 STREQUAL _expected_sha256)
        return()
      endif()
      message(WARNING "  Cached file hash mismatch; downloading again: ${output_path}")
      file(REMOVE "${output_path}")
    else()
      return()
    endif()
  endif()

  message(STATUS "  Downloading: ${url}")
  _driver_download_with_retries("${url}" "${output_path}" "${_expected_sha256}")
endfunction()

# ---------------------------------------------------------------------------
# nefcon  (zip with architecture subdirectories)
# ---------------------------------------------------------------------------
function(_fetch_nefcon)
  message(STATUS "Fetching nefcon ${NEFCON_VERSION} ...")
  set(_zip_url "https://github.com/${_NEFCON_REPO}/releases/download/${NEFCON_VERSION}/nefcon_${NEFCON_VERSION}.zip")
  set(_zip "${DRIVER_DEPS_CACHE}/nefcon-${NEFCON_VERSION}.zip")
  set(_marker "${NEFCON_DRIVER_DIR}/.release-version")
  set(_expected_marker "${NEFCON_VERSION}:${_NEFCON_EFFECTIVE_SHA256}")

  set(_stamp_ok FALSE)
  if(EXISTS "${_marker}")
    file(READ "${_marker}" _current)
    string(STRIP "${_current}" _current)
    if("${_current}" STREQUAL "${_expected_marker}")
      set(_stamp_ok TRUE)
    endif()
  endif()

  if(NOT _stamp_ok AND EXISTS "${NEFCON_DRIVER_DIR}")
    message(STATUS "  nefcon cache is not ${NEFCON_VERSION}; clearing ${NEFCON_DRIVER_DIR}")
    file(REMOVE_RECURSE "${NEFCON_DRIVER_DIR}")
  endif()

  _driver_download("${_zip_url}" "${_zip}" "${_NEFCON_EFFECTIVE_SHA256}")

  if(EXISTS "${_zip}" AND NOT EXISTS "${NEFCON_DRIVER_DIR}/nefconw.exe")
    set(_tmp "${DRIVER_DEPS_CACHE}/_nefcon_extract")
    file(REMOVE_RECURSE "${_tmp}")
    file(ARCHIVE_EXTRACT INPUT "${_zip}" DESTINATION "${_tmp}")
    file(MAKE_DIRECTORY "${NEFCON_DRIVER_DIR}")
    file(COPY_FILE "${_tmp}/x64/nefconw.exe" "${NEFCON_DRIVER_DIR}/nefconw.exe")
    file(WRITE "${_marker}" "${_expected_marker}\n")
    file(REMOVE_RECURSE "${_tmp}")
    message(STATUS "  Extracted nefconw.exe (x64) to ${NEFCON_DRIVER_DIR}")
  endif()
endfunction()

# Pinned installer bundled into the package so installation never downloads it.
function(_fetch_vigembus)
  set(_url
    "https://github.com/nefarius/ViGEmBus/releases/download/${VIGEMBUS_VERSION}/${VIGEMBUS_ASSET_NAME}")
  _driver_download("${_url}" "${VIGEMBUS_INSTALLER}" "${VIGEMBUS_SHA256}")
endfunction()

# ---------------------------------------------------------------------------
# Execute all fetches
# ---------------------------------------------------------------------------
_fetch_nefcon()
_fetch_vigembus()

# ---------------------------------------------------------------------------
# Verify critical files (per-driver, so optional drivers can be skipped
# individually when DRIVER_DEPS_REQUIRED=OFF, e.g. fork-PR CI).
# ---------------------------------------------------------------------------
function(_check_driver name available_var)
  set(_missing)
  foreach(_f ${ARGN})
    if(NOT EXISTS "${_f}")
      list(APPEND _missing "${_f}")
    endif()
  endforeach()
  if(_missing)
    string(REPLACE ";" "\n  " _list "${_missing}")
    if(DRIVER_DEPS_REQUIRED)
      message(FATAL_ERROR
        "Missing ${name} driver dependencies:\n  ${_list}\n"
        "To skip downloads: -DFETCH_DRIVER_DEPS=OFF (provide files manually in ${DRIVER_DEPS_CACHE}).\n"
        "To make missing drivers non-fatal (e.g. for fork-PR CI): -DDRIVER_DEPS_REQUIRED=OFF.")
    else()
      message(WARNING
        "Missing ${name} driver dependencies (packaging will skip this driver):\n  ${_list}")
    endif()
    set(${available_var} FALSE CACHE INTERNAL "" FORCE)
  else()
    set(${available_var} TRUE CACHE INTERNAL "" FORCE)
  endif()
endfunction()

_check_driver("nefcon" NEFCON_DRIVER_AVAILABLE
    "${NEFCON_DRIVER_DIR}/nefconw.exe")
_check_driver("ViGEmBus" VIGEMBUS_AVAILABLE
    "${VIGEMBUS_INSTALLER}")
