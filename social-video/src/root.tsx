import React from 'react';
import {Composition} from 'remotion';
import {AircadeOverview} from './video';

export const Root: React.FC = () => (
  <Composition
    id="AircadeOverview"
    component={AircadeOverview}
    durationInFrames={360}
    fps={30}
    width={1920}
    height={1080}
  />
);
