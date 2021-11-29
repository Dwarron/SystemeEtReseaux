#!/bin/bash

numeroRobot=$1			#numero du robot passe en parametre dans le gestionnaire du jeu
partieFini=false		#boolean pour savoir si la partie est finie
topDepart=false			#boolean pour lancer la partie
cartesRobot=()			#les cartes que le robot possede
carteCourante=0			#la carte joué par le robot

#methode recupere les cartes 
waitCartes()
{	
	#Envoie au gestionnaire du jeu que le joueur a recu les cartes
	echo "Robot $numeroRobot a recu ses cartes." | nc localhost 9091 | echo "Vous avez recu vos cartes." 
	
	for i in $(eval echo {1..$(wc -w tmp/cartePartie | cut -d" " -f1)}); #nombre d'élément dans le fichier
	do	
		cartesRobot+=($(echo $(cat tmp/cartePartie) | cut -d" " -f$i))	
	done
	echo ${cartesRobot[*]} #phase de tester a enlever
	echo "" > tmp/cartePartie
}

#methode qui attend le top depart
waitTopDepart()
{	
	#Envoyer au serveur que le joueur a recu le top depart
	echo "Robot $numeroRobot a recu le top depart." | nc -l -p 9092 | echo "Debut de la partie"
}

#methode qui essaye de faire jouer le robot au meilleur moment
jouerRobot()
{
	#algo pour essayer de faire jouer un robot au bon moment :
	carteCourante=${cartesRobot[0]} 
	
	#randomValue=$(( $((1 + $RANDOM % 8)) % 10 ))
	#time=$(($carteCourante * $randomValue))
	
	#pour la phase de test 
	sleep 0

	#on envoie la carte choisie au gestionnaire de jeu
	#echo jouerCarte $carteCourante | nc localhost 9091
	
	#ecrit la valeur de la carte dans carteAJouer
	echo $carteCourante > tmp/carteAJouer
	
	#ecrit le num du robot dans numJoueur
	echo $numeroRobot > tmp/numJoueur
	
	echo "Robot $numeroRobot a jouer la carte $carteCourante" | nc localhost 9093 

	#on enleve la carte des cartes disponible pour le robot
	cartesRobot=( ${cartesRobot[*]/$carteCourante} )
}

startGame()
{
	#avant de commencer la partie on attend les cartes
	waitCartes
	
	#quand on a recu les cartes on attend le top depart
	waitTopDepart
	
	while [ $partieFini == "false" ]
	do
		#avant tout on verifie si le robot a encores des cartes
		if (( ${#cartesRobot[*]} == 0 ));
		then
			
			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					onAttend=false
					waitCartes
				fi
			done
		else
			jouerRobot
		fi
	done
}

startGame
