import { useRef } from "react";
import { View, Text, Dimensions } from "react-native";
import {
  GestureDetector,
  Gesture,
} from "react-native-gesture-handler";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
  interpolate,
  Extrapolation,
} from "react-native-reanimated";
import type { Question } from "@/lib/api";

const { width: SCREEN_W } = Dimensions.get("window");
const SWIPE_THRESHOLD = SCREEN_W * 0.3;

interface Props {
  question: Question;
  onSwipeLeft: () => void;
  onSwipeRight: () => void;
  isTop: boolean;
}

export function SwipeCard({ question, onSwipeLeft, onSwipeRight, isTop }: Props) {
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const revealed = useSharedValue(false);

  const tap = Gesture.Tap().onEnd(() => {
    revealed.value = !revealed.value;
  });

  const pan = Gesture.Pan()
    .enabled(isTop)
    .onUpdate((e) => {
      translateX.value = e.translationX;
      translateY.value = e.translationY * 0.2;
    })
    .onEnd((e) => {
      if (e.translationX > SWIPE_THRESHOLD) {
        translateX.value = withSpring(SCREEN_W * 1.5);
        runOnJS(onSwipeRight)();
      } else if (e.translationX < -SWIPE_THRESHOLD) {
        translateX.value = withSpring(-SCREEN_W * 1.5);
        runOnJS(onSwipeLeft)();
      } else {
        translateX.value = withSpring(0);
        translateY.value = withSpring(0);
      }
    });

  const composed = Gesture.Simultaneous(tap, pan);

  const cardStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: translateX.value },
      { translateY: translateY.value },
      {
        rotate: `${interpolate(
          translateX.value,
          [-SCREEN_W, 0, SCREEN_W],
          [-15, 0, 15],
          Extrapolation.CLAMP
        )}deg`,
      },
    ],
  }));

  const correctStyle = useAnimatedStyle(() => ({
    opacity: interpolate(
      translateX.value,
      [0, SWIPE_THRESHOLD],
      [0, 1],
      Extrapolation.CLAMP
    ),
  }));

  const wrongStyle = useAnimatedStyle(() => ({
    opacity: interpolate(
      translateX.value,
      [-SWIPE_THRESHOLD, 0],
      [1, 0],
      Extrapolation.CLAMP
    ),
  }));

  const isMultiple = question.type === "multiple_choice" && question.options;
  const optionLabels = isMultiple ? Object.entries(question.options!) : [];

  return (
    <GestureDetector gesture={composed}>
      <Animated.View
        style={cardStyle}
        className="absolute inset-x-4 rounded-2xl bg-base-200 p-6 shadow-xl"
      >
        {/* Swipe labels */}
        <Animated.View
          style={correctStyle}
          className="absolute left-4 top-4 rounded-lg border-2 border-green-500 px-3 py-1"
        >
          <Text className="font-bold text-green-500">CORRECT</Text>
        </Animated.View>
        <Animated.View
          style={wrongStyle}
          className="absolute right-4 top-4 rounded-lg border-2 border-red-500 px-3 py-1"
        >
          <Text className="font-bold text-red-500">SKIP</Text>
        </Animated.View>

        <Text className="text-base leading-6 text-white">{question.content}</Text>

        {isMultiple && (
          <View className="mt-4 gap-2">
            {optionLabels.map(([key, value]) => (
              <View
                key={key}
                className="flex-row items-center rounded-lg bg-base-100 px-3 py-2"
              >
                <Text className="mr-2 font-bold text-primary">{key}</Text>
                <Text className="flex-1 text-sm text-gray-300">{value}</Text>
              </View>
            ))}
          </View>
        )}

        <View className="mt-6 border-t border-base-100 pt-4">
          <Text className="text-xs text-gray-500">Tap to reveal answer</Text>
          <Text className="mt-1 text-sm font-semibold text-green-400">
            Answer: {question.correct_answer}
          </Text>
          {question.explanation && (
            <Text className="mt-2 text-xs text-gray-400">
              {question.explanation}
            </Text>
          )}
        </View>

        <View className="mt-4 flex-row justify-between">
          <Text className="text-xs text-gray-600">← Swipe to skip</Text>
          <Text className="text-xs text-gray-600">Swipe correct →</Text>
        </View>
      </Animated.View>
    </GestureDetector>
  );
}
