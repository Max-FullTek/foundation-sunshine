# Keep the full CPACK_PACKAGE_VERSION for diagnostics and installed metadata.
# Only the installer UI uses this shorter, human-readable label.
function(sunshine_installer_display_version version output)
    string(REGEX REPLACE "^v" "" display "${version}")
    string(REGEX REPLACE "\\.杂鱼$" "" display "${display}")
    # Git's abbreviated commits are at least seven characters. Keep ordinary
    # numeric patch versions and six-digit local build timestamps intact here.
    if(display MATCHES "\\.([0-9a-fA-F]+)$")
        string(LENGTH "${CMAKE_MATCH_1}" suffix_length)
        if(suffix_length GREATER_EQUAL 7)
            string(REGEX REPLACE "\\.[0-9a-fA-F]+$" "" display "${display}")
        endif()
    endif()
    if(display MATCHES "^0\\.0\\.0($|\\.)" OR display MATCHES "^manual-")
        set(label "Development build")
    elseif(display MATCHES "^([0-9][0-9][0-9][0-9]\\.[0-9]+)\\.[0-9]+")
        set(label "v${CMAKE_MATCH_1}")
    else()
        set(label "v${display}")
    endif()
    set(${output} "${label}" PARENT_SCOPE)
endfunction()
