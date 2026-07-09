// JITSI_CUSTOM_15_USERS — live server-dən götürülmüş 15 nəfərlik qrup konfiqi

config.channelLastN = 15;
config.resolution = 720;
config.constraints = {
    video: {
        height: { ideal: 720, max: 720, min: 180 }
    }
};

config.enableSimulcast = true;
config.disableSimulcast = false;
config.enableLayerSuspension = true;

config.p2p = {
    enabled: true,
    stunServers: [
        { urls: 'stun:meet-jit-si-turnrelay.jitsi.net:443' }
    ]
};

config.startAudioMuted = 10;
config.startVideoMuted = 0;
config.enableNoAudioDetection = true;
config.enableNoisyMicDetection = true;

config.prejoinPageEnabled = true;
config.enableWelcomePage = true;

config.analytics = {};
config.disableThirdPartyRequests = true;

config.toolbarButtons = [
    'microphone', 'camera', 'desktop', 'chat',
    'raisehand', 'participants-pane', 'tileview',
    'fullscreen', 'hangup', 'settings', 'recording'
];

config.filmstrip = {
    disableStageFilmstrip: false
};

config.maxParticipants = 20;

// Server-side recording (Jibri)
config.recordingService = {
    enabled: true,
    sharingEnabled: false,
    hideStorageWarning: true
};
config.liveStreamingEnabled = false;
config.fileRecordingsEnabled = true;
config.fileRecordingsServiceEnabled = false;
config.fileRecordingsServiceSharingEnabled = false;
config.hiddenDomain = 'recorder.__DOMAIN__';
