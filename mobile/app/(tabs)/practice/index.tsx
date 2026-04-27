import { useState, useCallback, useRef } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  Dimensions,
} from "react-native";
import { useQuery, useMutation } from "@tanstack/react-query";
import { useLocalSearchParams } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { practiceApi, type Question } from "@/lib/api";
import { SwipeCard } from "@/components/SwipeCard";

const { height: SCREEN_H } = Dimensions.get("window");

interface Answer {
  question_id: string;
  answer: string;
  is_correct: boolean;
  time_ms: number;
}

export default function PracticeScreen() {
  const { courseId } = useLocalSearchParams<{ courseId?: string }>();
  const [cardIndex, setCardIndex] = useState(0);
  const [answers, setAnswers] = useState<Answer[]>([]);
  const [done, setDone] = useState(false);
  const startMs = useRef(Date.now());

  const { data, isLoading } = useQuery({
    queryKey: ["practice", courseId],
    queryFn: () => practiceApi.questions(courseId ?? "", 20),
    enabled: !!courseId,
  });

  const recordMutation = useMutation({
    mutationFn: (ans: Answer[]) =>
      practiceApi.recordAnswers(courseId ?? "", ans),
    onSuccess: () => {
      Alert.alert(
        "Session complete",
        `${answers.filter((a) => a.is_correct).length}/${answers.length} correct`
      );
    },
  });

  const handleSwipe = useCallback(
    (isCorrect: boolean) => {
      const questions = data?.data ?? [];
      const q = questions[cardIndex];
      if (!q) return;

      const elapsed = Date.now() - startMs.current;
      startMs.current = Date.now();

      const newAnswer: Answer = {
        question_id: q.id,
        answer: isCorrect ? q.correct_answer : "skipped",
        is_correct: isCorrect,
        time_ms: elapsed,
      };

      const updated = [...answers, newAnswer];
      setAnswers(updated);

      if (cardIndex + 1 >= questions.length) {
        setDone(true);
        recordMutation.mutate(updated);
      } else {
        setCardIndex((i) => i + 1);
      }
    },
    [cardIndex, data, answers, courseId]
  );

  if (!courseId) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-base-100 px-8">
        <Text className="text-center text-base text-gray-400">
          Select a course from the Courses tab to start practicing.
        </Text>
      </SafeAreaView>
    );
  }

  if (isLoading) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-base-100">
        <ActivityIndicator size="large" color="#7c3aed" />
      </SafeAreaView>
    );
  }

  const questions = data?.data ?? [];

  if (done || questions.length === 0) {
    const correct = answers.filter((a) => a.is_correct).length;
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-base-100 px-8">
        <Text className="text-3xl font-bold text-white">Session Done!</Text>
        <Text className="mt-3 text-5xl font-bold text-primary">
          {correct}/{answers.length}
        </Text>
        <Text className="mt-2 text-gray-400">correct answers</Text>
        <TouchableOpacity
          onPress={() => {
            setCardIndex(0);
            setAnswers([]);
            setDone(false);
          }}
          className="mt-8 rounded-xl bg-primary px-8 py-4"
        >
          <Text className="font-semibold text-white">Practice Again</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-base-100">
      <View className="px-4 pt-2">
        <Text className="text-2xl font-bold text-white">Practice</Text>
        <Text className="mt-1 text-sm text-gray-400">
          {cardIndex + 1} / {questions.length}
        </Text>
      </View>

      <View
        className="flex-1 items-center justify-center"
        style={{ height: SCREEN_H * 0.65 }}
      >
        {(() => {
          const visible = questions.slice(cardIndex, cardIndex + 2).reverse();
          return visible.map((q: Question, i: number) => (
            <SwipeCard
              key={q.id}
              question={q}
              isTop={i === visible.length - 1}
              onSwipeRight={() => handleSwipe(true)}
              onSwipeLeft={() => handleSwipe(false)}
            />
          ));
        })()}
      </View>
    </SafeAreaView>
  );
}
