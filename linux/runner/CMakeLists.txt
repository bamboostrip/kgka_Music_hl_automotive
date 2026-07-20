cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Application window icon. The PNGs are installed into the data directory
# alongside flutter_assets and loaded at runtime via the resource path.
set(APP_ICON_PNGS
  "resources/app_icon_16.png"
  "resources/app_icon_32.png"
  "resources/app_icon_64.png"
  "resources/app_icon_128.png"
  "resources/app_icon_256.png"
)
add_definitions(-DAPP_ICON_DIR="${INSTALL_BUNDLE_DATA_DIR}/app_icon")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Install the window icon PNGs into the bundle data directory.
install(FILES ${APP_ICON_PNGS} DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/app_icon"
  COMPONENT Runtime)
