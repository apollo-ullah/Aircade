import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Img,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {finishing} from './finishing-config';

const cyan = '#39d8ff';
const yellow = '#ffd43b';
const ink = '#04111f';

const fade = (frame: number, duration: number) =>
  interpolate(frame, [0, 8, duration - 8, duration], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

const Label: React.FC<{
  children: React.ReactNode;
  accent?: string;
  align?: 'left' | 'center';
}> = ({children, accent = cyan, align = 'left'}) => (
  <div
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 16,
      borderRadius: 999,
      padding: '12px 24px',
      background: 'rgba(3, 14, 28, 0.8)',
      border: `2px solid ${accent}`,
      color: 'white',
      fontFamily: 'Inter, Arial, sans-serif',
      fontSize: 30,
      fontWeight: 850,
      letterSpacing: 2,
      textTransform: 'uppercase',
      boxShadow: `0 0 42px ${accent}44`,
      alignSelf: align === 'center' ? 'center' : 'flex-start',
    }}
  >
    <span style={{width: 12, height: 12, borderRadius: 12, background: accent}} />
    {children}
  </div>
);

const TrendCaption: React.FC<{
  lead?: string;
  accent: string;
  detail: string;
  accentColor?: string;
  duration: number;
}> = ({lead, accent, detail, duration, accentColor = cyan}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({frame, fps, config: {damping: 16, stiffness: 190, mass: 0.7}});
  const exit = interpolate(frame, [duration - 12, duration - 1], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 106}}>
      <div
        style={{
          opacity: enter * exit,
          transform: `translateY(${(1 - enter) * 52}px) scale(${0.9 + enter * 0.1})`,
          textAlign: 'center',
          filter: 'drop-shadow(0 16px 28px rgba(0,0,0,.62))',
        }}
      >
        <div
          style={{
            display: 'inline-block',
            padding: '16px 28px 12px',
            borderRadius: 22,
            background: 'rgba(3, 8, 15, .68)',
            border: '1px solid rgba(255,255,255,.22)',
            backdropFilter: 'blur(18px)',
            color: '#f8f7f2',
            fontFamily: 'Helvetica Neue, Inter, Arial Black, sans-serif',
            fontSize: 88,
            lineHeight: 0.9,
            fontStyle: 'italic',
            fontWeight: 950,
            letterSpacing: -4,
            textTransform: 'uppercase',
          }}
        >
          {lead ? `${lead} ` : ''}
          <span style={{color: accentColor}}>{accent}</span>
        </div>
        <div
          style={{
            marginTop: 14,
            color: 'rgba(255,255,255,.82)',
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
            fontSize: 22,
            fontWeight: 700,
            letterSpacing: 5,
            textTransform: 'uppercase',
          }}
        >
          {detail}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const DialogueCaption: React.FC<{
  lines: readonly string[];
  emphasis: string;
  duration: number;
  reaction?: boolean;
  bottom?: number;
}> = ({lines, emphasis, duration, reaction = false, bottom}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({
    frame,
    fps,
    config: {damping: 20, stiffness: 220, mass: 0.65},
  });
  const exit = interpolate(frame, [duration - 6, duration], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const accent = reaction
    ? finishing.captions.reactionAccent
    : finishing.captions.accent;

  const renderLine = (line: string) => {
    const start = line.indexOf(emphasis);
    if (start === -1) return line;
    return (
      <>
        {line.slice(0, start)}
        <span style={{color: accent}}>{emphasis}</span>
        {line.slice(start + emphasis.length)}
      </>
    );
  };

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'flex-end',
        alignItems: 'center',
        paddingBottom: bottom ?? finishing.captions.bottom,
        pointerEvents: 'none',
      }}
    >
      <div
        style={{
          maxWidth: finishing.captions.maxWidth,
          opacity: enter * exit,
          transform: `translateY(${(1 - enter) * 28}px) scale(${0.96 + enter * 0.04})`,
          padding: '13px 27px 12px',
          borderRadius: 18,
          background: finishing.captions.background,
          border: '1px solid rgba(255,255,255,.2)',
          boxShadow: '0 14px 40px rgba(0,0,0,.46)',
          color: '#fffdf7',
          fontFamily: 'Helvetica Neue, Inter, Arial Black, sans-serif',
          fontSize: finishing.captions.fontSize,
          fontWeight: 950,
          fontStyle: 'italic',
          lineHeight: 0.94,
          letterSpacing: -2.6,
          textAlign: 'center',
          textTransform: 'uppercase',
          textShadow: '0 3px 12px rgba(0,0,0,.8)',
        }}
      >
        {lines.map((line, index) => (
          <React.Fragment key={line}>
            {index > 0 ? <br /> : null}
            {renderLine(line)}
          </React.Fragment>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const FilmFinish: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(135deg, rgba(22,72,94,.16), transparent 43%, rgba(255,178,116,.1))',
          mixBlendMode: 'soft-light',
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% 43%, transparent 46%, rgba(0,0,0,${finishing.grade.vignetteOpacity}) 116%)`,
        }}
      />
      <AbsoluteFill
        style={{
          inset: -80,
          backgroundImage: `url("${staticFile('grain.svg')}")`,
          backgroundRepeat: 'repeat',
          opacity: finishing.grade.grainOpacity,
          mixBlendMode: 'overlay',
          transform: `translate(${(frame % 7) * 9}px, ${(frame % 5) * -11}px)`,
        }}
      />
    </AbsoluteFill>
  );
};

const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, 42], [1.14, 1.03], {
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <OffthreadVideo
        src={staticFile('human.mp4')}
        startFrom={30}
        muted
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: `scale(${zoom})`,
          filter: finishing.grade.human,
        }}
      />
      <AbsoluteFill
        style={{
          background: 'linear-gradient(180deg, rgba(3,10,18,.12), rgba(3,10,18,.06) 48%, rgba(3,10,18,.6))',
        }}
      />
      <AbsoluteFill style={{padding: 72}}>
        <Label accent={yellow}>Hack the North · 2026</Label>
      </AbsoluteFill>
      <Sequence from={91} durationInFrames={27}>
        <TrendCaption lead="Meet" accent="Aircade." detail="Your earbuds · the controller" duration={27} />
      </Sequence>
    </AbsoluteFill>
  );
};

const PlayProof: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({frame, fps, config: {damping: 18, stiffness: 140}});
  const sceneEnter = interpolate(
    frame,
    [0, finishing.transitions.frames],
    [0, 1],
    {extrapolateRight: 'clamp'},
  );
  const pan = interpolate(frame, [0, 105], [1.08, 1.18], {extrapolateRight: 'clamp'});

  return (
    <AbsoluteFill
      style={{
        background: '#06152a',
        overflow: 'hidden',
        opacity: sceneEnter,
        transform: `translateX(${(1 - sceneEnter) * finishing.transitions.pushPixels}px)`,
      }}
    >
      <OffthreadVideo
        src={staticFile('astra.mp4')}
        startFrom={24 * 30}
        playbackRate={1.25}
        muted
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: `scale(${pan})`,
          filter: finishing.grade.gameplayBackground,
        }}
      />
      <AbsoluteFill style={{background: 'linear-gradient(135deg, #061225aa, #073d5baa)'}} />
      <AbsoluteFill style={{padding: 70, alignItems: 'center', justifyContent: 'center'}}>
        <div
          style={{
            width: 1460,
            height: 785,
            borderRadius: 36,
            overflow: 'hidden',
            border: '2px solid rgba(210,240,246,.72)',
            boxShadow: '0 30px 100px rgba(0,0,0,.55), 0 0 70px rgba(41,214,255,.2)',
            transform: `translateY(${(1 - enter) * 70}px) scale(${0.93 + enter * 0.07})`,
          }}
        >
          <OffthreadVideo
            src={staticFile('astra.mp4')}
            startFrom={24 * 30}
            playbackRate={1.25}
            muted
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              filter: finishing.grade.gameplayForeground,
            }}
          />
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{padding: 72}}>
        <Label>AirPod ↔ Codex</Label>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const WinCard: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = spring({frame, fps, config: {damping: 14, stiffness: 150}});
  const sceneEnter = interpolate(
    frame,
    [0, finishing.transitions.frames],
    [0, 1],
    {extrapolateRight: 'clamp'},
  );
  const zoom = interpolate(frame, [0, 78], [1.12, 1.02], {extrapolateRight: 'clamp'});

  return (
    <AbsoluteFill
      style={{
        background: ink,
        overflow: 'hidden',
        opacity: sceneEnter,
        transform: `translateX(${(1 - sceneEnter) * finishing.transitions.pushPixels}px)`,
      }}
    >
      <Img
        src={staticFile('thumbnail.png')}
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: `scale(${zoom})`,
          filter: finishing.grade.endCard,
        }}
      />
      <AbsoluteFill
        style={{background: 'linear-gradient(180deg, rgba(0,10,28,.05), rgba(0,7,22,.92) 88%)'}}
      />
      <AbsoluteFill style={{padding: '72px 86px', justifyContent: 'flex-end'}}>
        <div
          style={{
            opacity: fade(frame, 78),
            transform: `translateY(${(1 - pop) * 46}px)`,
            display: 'flex',
            alignItems: 'flex-end',
            justifyContent: 'space-between',
            gap: 40,
          }}
        >
          <div>
            <Label accent={yellow}>Aircade</Label>
            <div
              style={{
                marginTop: 20,
                color: 'white',
                fontFamily: 'Inter, Arial Black, Arial, sans-serif',
                fontSize: 70,
                fontWeight: 950,
                lineHeight: 0.98,
                letterSpacing: -2,
                textShadow: '0 8px 36px rgba(0,0,0,.7)',
              }}
            >
              YOUR EARBUDS.
              <br />
              <span style={{color: cyan}}>THE CONTROLLER.</span>
            </div>
          </div>
          <div
            style={{
              textAlign: 'right',
              color: 'white',
              fontFamily: 'Inter, Arial, sans-serif',
              fontWeight: 900,
              fontSize: 33,
              lineHeight: 1.25,
              textShadow: '0 4px 20px rgba(0,0,0,.75)',
            }}
          >
            <div style={{color: yellow, fontSize: 46}}>3RD PLACE</div>
            CODEX TRACK
            <br />
            HTN SEMIFINALIST
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const AircadeOverview: React.FC = () => (
  <AbsoluteFill style={{background: ink}}>
    <Sequence from={0} durationInFrames={126} premountFor={30}>
      <Hook />
    </Sequence>
    <Sequence from={118} durationInFrames={164} premountFor={30}>
      <PlayProof />
    </Sequence>
    <Sequence from={274} durationInFrames={86} premountFor={30}>
      <WinCard />
    </Sequence>

    <FilmFinish />

    {finishing.captions.cues.map((cue) => (
      <Sequence key={cue.from} from={cue.from} durationInFrames={cue.duration}>
        <DialogueCaption
          lines={cue.lines}
          emphasis={cue.emphasis}
          duration={cue.duration}
          reaction={'reaction' in cue ? cue.reaction : false}
          bottom={'bottom' in cue ? cue.bottom : undefined}
        />
      </Sequence>
    ))}

    <Audio src={staticFile('room-audio-mastered.wav')} volume={finishing.audio.roomVolume} />
    <Sequence from={116} durationInFrames={14}>
      <Audio src={staticFile('impact.ogg')} volume={finishing.audio.impactVolume} />
    </Sequence>
    <Sequence from={272} durationInFrames={18}>
      <Audio src={staticFile('confirm.ogg')} volume={finishing.audio.confirmVolume} />
    </Sequence>
  </AbsoluteFill>
);
