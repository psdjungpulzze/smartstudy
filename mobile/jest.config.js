module.exports = {
  testEnvironment: require.resolve(
    "react-native/jest/react-native-env.js"
  ),
  setupFiles: [require.resolve("react-native/jest/setup.js")],
  setupFilesAfterEnv: ["<rootDir>/jest.setup.ts"],
  transform: {
    "^.+\\.[jt]sx?$": [
      "babel-jest",
      {
        caller: { name: "metro", bundler: "metro", platform: "ios" },
      },
    ],
    "^.+\\.(bmp|gif|jpg|jpeg|png|psd|svg|webp|xml|m4v|mov|mp4|mpeg|mpg|webm|aac|aiff|caf|m4a|mp3|wav|html|pdf|yaml|yml|otf|ttf|zip|heic|avif|db)$": require.resolve(
      "jest-expo/src/preset/assetFileTransformer.js"
    ),
  },
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/$1",
    "\\.(css|less|sass|scss)$": "<rootDir>/__tests__/fileMock.js",
  },
  haste: {
    defaultPlatform: "ios",
    platforms: ["android", "ios", "native"],
  },
  transformIgnorePatterns: [
    "node_modules/(?!((jest-)?react-native|@react-native(-community)?)|expo(nent)?|@expo(nent)?/.*|@expo-google-fonts/.*|react-navigation|@react-navigation/.*|@unimodules/.*|unimodules|sentry-expo|native-base|react-native-svg|nativewind)",
  ],
  testPathIgnorePatterns: ["/node_modules/", "/__tests__/fileMock\\.js$"],
  collectCoverageFrom: [
    "lib/**/*.{ts,tsx}",
    "store/**/*.{ts,tsx}",
    "components/**/*.{ts,tsx}",
    "app/**/*.{ts,tsx}",
    "!**/*.d.ts",
    "!**/node_modules/**",
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80,
    },
  },
};
