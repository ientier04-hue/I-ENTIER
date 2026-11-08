import React, { useEffect, useMemo, useRef } from 'react';
import { Pressable, type PressableProps, type StyleProp, type ViewProps, type ViewStyle } from 'react-native';
import Animated, { cancelAnimation, Easing, FadeInDown, ReduceMotion, useAnimatedStyle, useReducedMotion, useSharedValue, withSequence, withTiming } from 'react-native-reanimated';

const AnimatedPressable = Animated.createAnimatedComponent(Pressable);
const timing = { duration: 180, easing: Easing.out(Easing.cubic), reduceMotion: ReduceMotion.System };

export function MotionPressable({ style, onPressIn, onPressOut, disabled, ...props }: Omit<PressableProps, 'style'> & { style?: StyleProp<ViewStyle> }) {
  const scale = useSharedValue(1);
  const reduceMotion = useReducedMotion();
  const animatedStyle = useAnimatedStyle(() => ({ transform: [{ scale: scale.get() }] }));
  useEffect(() => {
    if (disabled || reduceMotion) { cancelAnimation(scale); scale.set(1); }
    return () => cancelAnimation(scale);
  }, [disabled, reduceMotion, scale]);
  return <AnimatedPressable {...props} disabled={disabled} style={[style, animatedStyle]}
    onPressIn={event => {
      if (!disabled && !reduceMotion) scale.set(withTiming(.96, { ...timing, duration: 90 }));
      onPressIn?.(event);
    }}
    onPressOut={event => { scale.set(withTiming(1, timing)); onPressOut?.(event); }}/>;
}

export function MotionCard({ index = 0, ...props }: ViewProps & { index?: number }) {
  const entering = useMemo(() => FadeInDown.duration(320).delay(Math.min(Math.max(index, 0), 5) * 45)
    .easing(Easing.out(Easing.cubic)).withInitialValues({ translateY: 14 }).reduceMotion(ReduceMotion.System), [index]);
  return <Animated.View {...props} entering={entering}/>;
}

export function SelectionPulse({ active, children }: { active: boolean; children: React.ReactNode }) {
  const scale = useSharedValue(1);
  const previous = useRef(active);
  const reduceMotion = useReducedMotion();
  const style = useAnimatedStyle(() => ({ transform: [{ scale: scale.get() }] }));
  useEffect(() => {
    if (active && !previous.current && !reduceMotion) {
      scale.set(withSequence(withTiming(1.18, { ...timing, duration: 100 }), withTiming(1, timing)));
    } else { cancelAnimation(scale); scale.set(1); }
    previous.current = active;
    return () => cancelAnimation(scale);
  }, [active, reduceMotion, scale]);
  return <Animated.View pointerEvents="none" style={style}>{children}</Animated.View>;
}
