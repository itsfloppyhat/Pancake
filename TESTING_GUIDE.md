# 🧪 Pancake Testing Guide

## ✅ **Ready to Test!**

The AI music curation system is now fully implemented and ready for testing. Here's how to test each component:

## 🎯 **Testing Checklist**

### **1. ChatGPT Setup (iPhone App)**
- [ ] Open Pancake app on iPhone
- [ ] Go to **Profile** tab → **AI Music Curation**
- [ ] Enter your OpenAI API key from platform.openai.com
- [ ] Tap **"Test Connection"** - should show "✅ Success!"
- [ ] Tap **"Done"** to save

### **2. Music Preferences Setup (iPhone App)**
- [ ] Go to **Profile** tab → **Music Preferences**
- [ ] Tap **"Connect"** for Apple Music authorization
- [ ] Tap **"Auto-Populate from Apple Music"** to import your music
- [ ] Verify your favorite artists and songs appear
- [ ] Set mood preferences for different intensities

### **3. Connected Mode Testing (iPhone + Watch)**
- [ ] Ensure iPhone and Watch are connected
- [ ] Start a workout on the Watch
- [ ] Verify music controls appear on Watch
- [ ] Check that AI suggestions are generated
- [ ] Test play/pause/skip controls
- [ ] Verify songs change based on workout intensity

### **4. Standalone Mode Testing (Watch Only)**
- [ ] Put iPhone in airplane mode or move away
- [ ] Start a workout on the Watch
- [ ] Verify standalone music controls appear
- [ ] Test playlist selection
- [ ] Verify music adapts to heart rate changes

### **5. Workout Flow Testing**
- [ ] Create a workout plan with different intensities
- [ ] Start the workout
- [ ] Verify GPS tracking works
- [ ] Check heart rate monitoring
- [ ] Test music transitions between segments
- [ ] Complete workout and verify data is saved

## 🎵 **Expected Behavior**

### **Connected Mode (iPhone + Watch):**
- **Starting song**: AI suggests based on workout plan and preferences
- **During workout**: Songs change based on heart rate and effort
- **Interval changes**: AI suggests appropriate songs for upcoming intensity
- **Real-time adaptation**: Music adapts to your performance

### **Standalone Mode (Watch Only):**
- **Playlist selection**: Automatically chooses appropriate playlists
- **Heart rate adaptation**: Switches between calming/energizing music
- **Basic controls**: Play, pause, skip, volume
- **Smart switching**: Adapts to workout intensity

## 🐛 **Troubleshooting**

### **ChatGPT Not Working:**
- Check API key is correct
- Verify internet connection
- Check OpenAI account has credits
- Test connection in settings

### **Music Not Playing:**
- Check Apple Music authorization
- Verify music library has content
- Check MediaPlayer permissions
- Try different playlists

### **Watch Not Connecting:**
- Check WatchConnectivity is enabled
- Verify both devices are signed in to same Apple ID
- Restart both devices if needed
- Check Bluetooth connection

### **GPS Issues:**
- Check location permissions
- Verify GPS status indicator
- Test in open area
- Check location accuracy

## 📱 **Test Scenarios**

### **Scenario 1: Easy 5K Run**
1. Create workout: 5K at easy effort
2. Start workout
3. Verify AI suggests relaxed song
4. Check music adapts to heart rate
5. Complete workout

### **Scenario 2: Interval Training**
1. Create workout: 4x 2min hard, 2min easy
2. Start workout
3. Verify starting song is appropriate
4. Check music changes for hard intervals
5. Verify recovery music is calming
6. Complete workout

### **Scenario 3: Standalone Watch**
1. Disconnect iPhone
2. Start workout on Watch
3. Verify playlist selection works
4. Check music adapts to effort
5. Test all music controls
6. Complete workout

## 🎯 **Success Criteria**

- ✅ ChatGPT API connects successfully
- ✅ Music preferences are populated
- ✅ AI suggests appropriate songs
- ✅ Music plays during workouts
- ✅ Watch controls work properly
- ✅ Standalone mode functions
- ✅ Workout data is saved
- ✅ No crashes or errors

## 🚀 **Ready to Go!**

The system is fully implemented and ready for testing. Start with the ChatGPT setup, then test the music preferences, and finally try a workout to see the AI music curation in action!

**Happy Testing!** 🎵🏃‍♂️🤖
