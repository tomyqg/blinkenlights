package de.blinkenlights.bmix.main;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

import de.blinkenlights.bmix.mixer.Layer;
import de.blinkenlights.bmix.mixer.Output;
import de.blinkenlights.bmix.network.BLPacketReceiver;
import de.blinkenlights.bmix.network.BLPacketReceiverThread;

/**
 * This class represents a BMixSession.
 */
public class BMixSession {
    private final Layer rootLayer;
    private final Map<BLPacketReceiver, List<Layer>> layerInputs;
    
    /**
     * An unmodifiable copy of the list given in the constructor.
     */
    private final List<BLPacketReceiverThread> receiverThreads;

    private final Semaphore semaphore = new Semaphore(0);
    private final long maxFrameInterval;
    
    /**
     * An unmodifiable copy of the list given in the constructor.
     */
    private final List<Output> outputs;

    /**
     * Sets up this configuration, creating the necessary receiver threads and
     * starting them.
     * 
     * @param rootLayer
     *            The special root layer for this configuration. It should not
     *            have a parent, and all other layers must be descendants of
     *            this layer.
     * @param outputs
     *            The outputs this session sends new frame data to.
     * @param layerInputs
     *            A map of each packet receiver to all the layers they feed data
     *            to.
     * @param outputs
     *            The outputs for this session
     */
    public BMixSession(Layer rootLayer, Map<BLPacketReceiver, List<Layer>> layerInputs, List<Output> outputs, long maxFrameInterval) {
        this.rootLayer = rootLayer;
        this.layerInputs = layerInputs;
        this.outputs = Collections.unmodifiableList(new ArrayList<Output>(outputs));
        this.maxFrameInterval = maxFrameInterval;
        
        List<BLPacketReceiverThread> threads = new ArrayList<BLPacketReceiverThread>();
        for (BLPacketReceiver r : layerInputs.keySet()) {
            BLPacketReceiverThread t = new BLPacketReceiverThread(r, semaphore, 1000);
            t.start();
            threads.add(t);
        }
        receiverThreads = Collections.unmodifiableList(threads);

    }

    public Layer getRootLayer() {
        return rootLayer;
    }
    
    public List<Layer> getLayersForReceiver(BLPacketReceiver r) {
        List<Layer> layers = layerInputs.get(r);
        if (layers == null) {
            return Collections.emptyList();
        } else {
            return layers;
        }
    }
    
    /**
     * Returns the list of receiver threads for this configuration. There will
     * be one thread per receiver.
     * 
     * @return A list you can't modify, so don't try.
     */
    public List<BLPacketReceiverThread> getReceiverThreads() {
        return receiverThreads;
    }
    
    /**
     * Returns the list of outputs for this configuration.
     * 
     * @return A list you can't modify, so don't try.
     */
    public List<Output> getOutputs() {
        return outputs;
    }

    /**
     * Waits either for one of the receiver threads to get a new packet
     * from its packet receiver, or until your thread is interrupted, whichever
     * comes first.
     */
    public void waitForNewPacket() {
        try {
            semaphore.tryAcquire(maxFrameInterval, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            // it's ok to pretend there was new data
        }
    }

}
