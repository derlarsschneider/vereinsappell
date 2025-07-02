// Hybrid App für Schützenvereine mit AWS Backend
import React, { useState, useEffect } from 'react';
import { Tabs, Tab } from '@/components/ui/tabs';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { sendPushNotification } from './utils/notifications';
import { createFine, fetchTermine, uploadPhoto, registerMemberWithQR } from './utils/api';

const App = () => {
  const [vereinName, setVereinName] = useState('');
  const [wappenUrl, setWappenUrl] = useState('');
  const [tab, setTab] = useState('termine');

  const Screens = {
    termine: <Termine />,
    strafgelder: <Strafgelder />,
    galerie: <Fotogalerie />,
    knobeln: <Knobeln />,
  };

  return (
    <div className="p-4">
      <div className="flex items-center space-x-4 mb-4">
        <Input placeholder="Vereinsname" value={vereinName} onChange={e => setVereinName(e.target.value)} />
        <Input placeholder="Wappen URL" value={wappenUrl} onChange={e => setWappenUrl(e.target.value)} />
        {wappenUrl && <img src={wappenUrl} alt="Wappen" className="h-12" />}
      </div>
      <Tabs value={tab} onValueChange={setTab}>
        <Tab value="termine">Termine</Tab>
        <Tab value="strafgelder">Strafgelder</Tab>
        <Tab value="galerie">Fotogalerie</Tab>
        <Tab value="knobeln">Knobeln</Tab>
      </Tabs>
      <Card className="mt-4">
        <CardContent>{Screens[tab]}</CardContent>
      </Card>
    </div>
  );
};

const Termine = () => {
  const [termine, setTermine] = useState([]);

  useEffect(() => {
    fetchTermine().then(setTermine);
  }, []);

  return (
    <div>
      {termine.map((t, idx) => (
        <div key={idx}>{t.title} - {t.date}</div>
      ))}
    </div>
  );
};

const Fotogalerie = () => {
  const [file, setFile] = useState(null);

  const handleUpload = () => {
    if (file) uploadPhoto(file);
  };

  return (
    <div className="space-y-2">
      <Input type="file" onChange={e => setFile(e.target.files[0])} />
      <Button onClick={handleUpload}>Hochladen</Button>
    </div>
  );
};

const Strafgelder = () => {
  const [isSpiess, setIsSpiess] = useState(false);
  const [memberId, setMemberId] = useState('');

  const handleStrafgeld = () => {
    if (isSpiess) {
      createFine(memberId).then(() => {
        sendPushNotification(memberId, 'Du hast ein Strafgeld erhalten!');
      });
    }
  };

  return (
    <div>
      {isSpiess && (
        <div className="space-y-2">
          <Input placeholder="Mitglied ID" value={memberId} onChange={e => setMemberId(e.target.value)} />
          <Button onClick={handleStrafgeld}>Strafgeld vergeben</Button>
        </div>
      )}
    </div>
  );
};

const Knobeln = () => {
  return <div>Spielmechanik wird hier implementiert (Timeout, Auswahl, Schätzung)</div>;
};

export default App;
