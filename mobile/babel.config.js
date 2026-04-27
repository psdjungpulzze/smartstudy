module.exports = function (api) {
  api.cache.using(() => process.env.NODE_ENV);
  const isTest = process.env.NODE_ENV === "test";

  if (isTest) {
    // Use babel-preset-expo without nativewind for test environment.
    // nativewind/babel returns a preset-shaped object that fails Babel plugin validation.
    return {
      presets: ["babel-preset-expo"],
    };
  }

  return {
    presets: [
      ["babel-preset-expo", { jsxImportSource: "nativewind" }],
    ],
    plugins: ["nativewind/babel"],
  };
};
