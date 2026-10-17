option(BUILD_WEB_UI "Build the web UI via npm" ON)
if(NOT BUILD_WEB_UI)
    return()
endif()
set(_panel_dir "${SUNSHINE_SOURCE_ASSETS_DIR}/common/sunshine-control-panel")
find_program(NPM npm REQUIRED)
set(_npm_command "${NPM}")
if(WIN32)
    list(PREPEND _npm_command cmd /D /C call)
endif()
set(_npm_flags)
if(NPM_OFFLINE)
    list(APPEND _npm_flags --offline)
endif()
set(_npm_stamp "${_panel_dir}/node_modules/.sunshine-cmake-dependencies")
add_custom_command(OUTPUT "${_npm_stamp}"
        COMMAND ${_npm_command} ci ${_npm_flags}
        COMMAND "${CMAKE_COMMAND}" -E touch "${_npm_stamp}"
        DEPENDS "${_panel_dir}/package.json" "${_panel_dir}/package-lock.json"
        WORKING_DIRECTORY "${_panel_dir}"
        COMMENT "Installing locked Web UI dependencies"
        VERBATIM)

# Track additions as well as edits; Vite config/plugins and prebuild scripts are
# inputs too. A deleted output page causes the complete bundle to rebuild.
file(GLOB_RECURSE _web_inputs CONFIGURE_DEPENDS LIST_DIRECTORIES FALSE
        "${_panel_dir}/webui/*" "${_panel_dir}/scripts/webui/*"
        "${_panel_dir}/src/renderer/*")
set(_web_outputs)
file(GLOB _web_pages RELATIVE "${_panel_dir}/webui"
        CONFIGURE_DEPENDS "${_panel_dir}/webui/*.html")
list(FILTER _web_pages EXCLUDE REGEX "^template_")
foreach(_page IN LISTS _web_pages)
    list(APPEND _web_outputs "${PROJECT_BINARY_DIR}/assets/web/${_page}")
endforeach()
set(_web_stamp "${PROJECT_BINARY_DIR}/web-ui.stamp")
add_custom_command(OUTPUT "${_web_stamp}" ${_web_outputs}
        COMMAND "${CMAKE_COMMAND}" -E env
            ${_npm_command} run build:webui -- --outDir "${PROJECT_BINARY_DIR}/assets/web"
        COMMAND "${CMAKE_COMMAND}" -E touch "${_web_stamp}"
        DEPENDS "${_npm_stamp}" ${_web_inputs}
        WORKING_DIRECTORY "${_panel_dir}"
        COMMENT "Building changed Web UI assets"
        VERBATIM)
add_custom_target(web-ui ALL DEPENDS "${_web_stamp}" ${_web_outputs})
