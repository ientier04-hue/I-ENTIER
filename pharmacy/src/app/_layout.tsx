import { Stack } from "expo-router";
import { GuestProvider } from "../useGuestAccess";

export default function Layout() {
  return <GuestProvider><Stack screenOptions={{ headerShown: false }} /></GuestProvider>;
}
